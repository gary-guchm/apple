
 
<# 
  OSD-LoadAllWindowsUpdates-4Keys.ps1
  需求：
    - 更新前将 4 个 SetPolicyDrivenUpdateSourceFor* 键设置为 0（使用 Windows Update）
    - 完成更新后将 4 个键全部恢复为 1
    - 运行 PSWindowsUpdate 进行扫描与安装（忽略重启）
    - 刷新策略 & 重启服务，记录日志
#>

# ---------------------------- 日志 ----------------------------
$LogPath = 'C:\temp\WU-Run.log'
function Write-Log($msg, [string]$level='INFO') {
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 's'), $level, $msg
    $line | Out-File -FilePath $LogPath -Append -Encoding UTF8
    Write-Output $line
}
Write-Log "Starting OSD Windows Update script (4 keys to 0, then restore to 1)."

# ---------------------------- 注册表路径 / 键 ----------------------------
$WUKey          = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$AUKey          = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
$KeysToToggle   = @(
    'SetPolicyDrivenUpdateSourceForDriverUpdates',
    'SetPolicyDrivenUpdateSourceForFeatureUpdates',
    'SetPolicyDrivenUpdateSourceForOtherUpdates',
    'SetPolicyDrivenUpdateSourceForQualityUpdates'
)

# 确保路径存在
foreach ($p in @($WUKey, $AUKey)) {
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null; Write-Log "Created missing registry path: $p" }
}

# ---------------------------- （可选）备份 WSUS 指针 ----------------------------
$originalUseWUServer    = (Get-ItemProperty -Path $AUKey -Name UseWUServer    -ErrorAction SilentlyContinue).UseWUServer
$originalWUServer       = (Get-ItemProperty -Path $WUKey -Name WUServer       -ErrorAction SilentlyContinue).WUServer
$originalWUStatusServer = (Get-ItemProperty -Path $WUKey -Name WUStatusServer -ErrorAction SilentlyContinue).WUStatusServer
Write-Log "Backup WSUS: UseWUServer=$originalUseWUServer; WUServer=$originalWUServer; WUStatusServer=$originalWUStatusServer"

# ---------------------------- 前置：禁用 WSUS 指针（如需）并设置 4 键为 0 ----------------------------
try {
    # 切换到 Windows Update（可选：禁用 WSUS 指针）
    Set-ItemProperty -Path $AUKey -Name UseWUServer -Type DWord -Value 0 -Force
    Remove-ItemProperty -Path $WUKey -Name WUServer       -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $WUKey -Name WUStatusServer -ErrorAction SilentlyContinue
    Write-Log "Temporarily disabled WSUS pointers (UseWUServer=0, removed WUServer/WUStatusServer)."

    # 确保允许访问互联网 WU
    Set-ItemProperty -Path $WUKey -Name 'DoNotConnectToWindowsUpdateInternetLocations' -Type DWord -Value 0 -Force

    # 将四个键全部设置为 0
    foreach ($name in $KeysToToggle) {
        Set-ItemProperty -Path $WUKey -Name $name -Type DWord -Value 0 -Force
        Write-Log "Set $name = 0"
    }

    # 刷新策略 & 重启服务
   # gpupdate /target:computer /force | Out-Null
    #Write-Log "Group Policy refreshed."
    Try { Restart-Service -Name wuauserv -Force -ErrorAction SilentlyContinue } Catch { Write-Log $_.Exception.Message 'WARN' }
    Try { Restart-Service -Name bits     -Force -ErrorAction SilentlyContinue } Catch { Write-Log $_.Exception.Message 'WARN' }
    Write-Log "Windows Update services restarted."
}
catch {
    Write-Log "Error while pre-switching sources: $($_.Exception.Message)" 'ERROR'
    throw
}

# ---------------------------- 安装 PSWindowsUpdate 模块 ----------------------------
function Install-PSModule {
    param([Parameter(Mandatory=$true)][String[]]$Modules)
    Write-Log "Checking PowerShell modules: $($Modules -join ', ')"
    try {
        $ProgressPreference = 'SilentlyContinue'
        if ([Net.ServicePointManager]::SecurityProtocol -notcontains 'Tls12' -and [Net.ServicePointManager]::SecurityProtocol -notcontains 'Tls13') {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        }

        if (!(Get-PackageProvider -ListAvailable -Name 'NuGet' -ErrorAction Ignore)) {
            Write-Log 'Installing NuGet package provider...'
            Install-PackageProvider -Name 'NuGet' -MinimumVersion 2.8.5.201 -Force
        }

        Register-PSRepository -Default -InstallationPolicy 'Trusted' -ErrorAction Ignore
        if ((Get-PSRepository -Name 'PSGallery' -ErrorAction Ignore).InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy 'Trusted'
        }

        foreach ($Module in $Modules) {
            if (!(Get-Module -ListAvailable -Name $Module -ErrorAction Ignore)) {
                Write-Log "Installing module: $Module"
                Install-Module -Name $Module -Force
            }
            Import-Module $Module -Force
        }
        Write-Log "Modules installed/imported."
    }
    catch {
        Write-Log "Unable to install/import modules: $($_.Exception.Message)" 'ERROR'
        throw
    }
}

try { Install-PSModule @('PSWindowsUpdate') }
catch { Write-Log "PSWindowsUpdate not available: $($_.Exception.Message)" 'ERROR'; throw }

# ---------------------------- 扫描与安装（忽略重启） ----------------------------

 Get-WUList -MicrosoftUpdate | Select Title, KB, Msrc 
try {
    Write-Log "Starting Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -Install -IgnoreReboot ..."
    Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -Install -IgnoreReboot
    Write-Log "Get-WindowsUpdate completed. See C:\temp\WU-Run.log"
}
catch {
    Write-Log "Error during Windows Update run: $($_.Exception.Message)" 'ERROR'
    # 即使失败也继续做还原
}

# ---------------------------- 还原：四键全部恢复成 1，WSUS 指针恢复 ----------------------------
try {
    # 还原四个键为 1
    foreach ($name in $KeysToToggle) {
        Set-ItemProperty -Path $WUKey -Name $name -Type DWord -Value 1 -Force
        Write-Log "Restore $name = 1"
    }

    # （可选）恢复 WSUS 指针
    if ($null -ne $originalUseWUServer) {
        Set-ItemProperty -Path $AUKey -Name UseWUServer -Type DWord -Value $originalUseWUServer -Force
        Write-Log "Restored UseWUServer=$originalUseWUServer"
    } else {
        Remove-ItemProperty -Path $AUKey -Name UseWUServer -ErrorAction SilentlyContinue
        Write-Log "Removed UseWUServer (no original value)."
    }

    if ($null -ne $originalWUServer) {
        Set-ItemProperty -Path $WUKey -Name WUServer -Type String -Value $originalWUServer -Force
        Write-Log "Restored WUServer=$originalWUServer"
    } else {
        Remove-ItemProperty -Path $WUKey -Name WUServer -ErrorAction SilentlyContinue
        Write-Log "Removed WUServer (no original value)."
    }

    if ($null -ne $originalWUStatusServer) {
        Set-ItemProperty -Path $WUKey -Name WUStatusServer -Type String -Value $originalWUStatusServer -Force
        Write-Log "Restored WUStatusServer=$originalWUStatusServer"
    } else {
        Remove-ItemProperty -Path $WUKey -Name WUStatusServer -ErrorAction SilentlyContinue
        Write-Log "Removed WUStatusServer (no original value)."
    }

    # 刷新策略 & 重启服务
    gpupdate /target:computer /force | Out-Null
    Write-Log "Group Policy refreshed (post-restore)."
    Try { Restart-Service -Name wuauserv -Force -ErrorAction SilentlyContinue } Catch { Write-Log $_.Exception.Message 'WARN' }
    Try { Restart-Service -Name bits     -Force -ErrorAction SilentlyContinue } Catch { Write-Log $_.Exception.Message 'WARN' }
    Write-Log "Windows Update services restarted (post-restore)."
}
catch {
    Write-Log "Error while restoring sources: $($_.Exception.Message)" 'ERROR'
    throw
}

Write-Log "OSD Windows Update“ 
