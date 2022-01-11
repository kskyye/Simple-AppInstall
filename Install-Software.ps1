
<# >(^_^)>  >(^_^)> --- SCRIPT SCOPE, PURPOSE & DETAILS --- <(^_^)<  <(^_^)<
#region Scope and Purpose

.:Written By Kristin Anderson
10.17.2017

--------------------------------------

.:Synopsis 
Install software based on certain conditions.
 
.:Description
To save time mass installing applications w/o reinstall every time (via GPO).  
 
.:Parameters
$uninstallFirst      $True or $False.  If a previous version of the software needs to be uninstalled before the new 
                     version can be installed set parameter to $True
$productID           String value.  If above is set to $True specify the software product code for the software
                     App product codes can be found in Registry - HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Uninstall.
 
.:Inputs
None. You cannot pipe objects for function. 
 
.:Outputs 
[COMPUTERNAME].txt                basic log file containing one line every time the script is run to indicate what action was taken
[COMPUTERNAME] Install.log        MSIESXEC verbose logging for installation of software.
[COMPUTERNAME] Un-Install.log     MSIESXEC verbose logging for un-installation of software.

  
.:Examples
InstallSoftware($False,"{92ACF23E-DD58-4877-AF87-4BF7FD669928}")
#>
#endregion
### <(^_^)> --- END SCOPE & PURPOSE REGION --- <(^_^)>



###DEFINE VARIABLES
$dateLong = Get-Date
$computerName = $env:COMPUTERNAME
<#Set location of log files.  Three txt files will be created per computer (script run log, verbose install and verbose uninstall.
Ensure that "Everyone" has Modify permissions at the share and file level.#>
$logFilePath = "\\fileserver1.sufs.local\InstallLogging\PaloAlto\"
$logFile = "$computerName.txt"
$MSIEXEClogFileInstall = "Verbose\$computerName Install.txt"
$MSIEXEClogFileUnInstall = "Verbose\$computerName Un-Install.txt"
#Set location of MSI installer file and any additional files to be copied to the computer's local drive.
$installPath = "\\jx-ph-dfsfile1\IT\Installs\Software- Palo Alto\"
$msiPackage = "GlobalProtect64-4.0.3.msi"
$customFile1 = "PortalAddress.reg"
#$customFile2 = "PortalAddress.reg"
#$customFile3 = "PortalAddress.reg"
###

###DEFINE INSTALLATION WORKFLOW FUNCTION
Function Install-Software
{
Param ($uninstallFirst,[string]$productID) 
    
    #Copy installation files, customizations, transforms, etc to local workstation.
    If (!(Test-Path "c:\Temp"))
    {
        New-Item -ItemType Directory -Force -Path "c:\Temp"
    }
    xcopy $installPath$msiPackage "C:\Temp" /Y
	xcopy $installPath$customFile1 "C:\Temp" /Y

    #If uninstallFirst parameter is set to true the old client will be uninstalled.
    If ($uninstallFirst -eq $True)
    {
        <#Check to see if a service is running that would prevent an unattended/silent uninstallation.  If the service is running stop 
        it and kill any accompanying process.#>
        If(Get-Service -Name "pangps" | Where {$_.status –eq 'running'})
        {
            net stop pangps
            timeout 5
            taskkill /IM pangpa.exe /f
        }

        <#Uninstall the application via msiexec.exe.  Software ID codes can be found in Registry Key
        HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Uninstall.#>
        msiexec.exe /I $productID /qn REMOVE=ALL /LV!* $logFilePath$MSIEXEClogFileUnInstall
        timeout 60
    }

    msiexec.exe /I "c:\Temp\$msiPackage" /quiet /LV!* $logFilePath$MSIEXEClogFileInstall
    timeout 30
    reg Import C:\Temp\$customFile1
    timeout 5

    net stop pangps
    net start pangps
}
###


###CODE FOR AUTOMATION/STARTUP GPO
##To use via startup script (GPO, etc); Remove the comment section ">" & ">", comment out the blocks of ###CODE below and above and automate run.
#Check to see if the client is already installed; if not, install the new version.
If (!(Reg Query "HKLM\SOFTWARE\Palo Alto Networks\GlobalProtect")) {
        Add-Content $logFilePath$logFile "$dateLong - No version of software was found on computer.  Installed current version."
        Install-Software($False)

#If existing version IS detected, get version number to determine if the version installed is current.
} ElseIf(Reg Query "HKLM\SOFTWARE\Palo Alto Networks\GlobalProtect") {
    #Set gpVersion Variable.
    $gpVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Palo Alto Networks\GlobalProtect").Version

    #If existing version is known old version, uninstall old version and install new.
    ## Change the $gpVersion variable to the number of the known previous version.
    If ($gpVersion -eq "3.1.1-27")
    {
        Write-Host "Old version of software found.  Initiating uninstallation of old and installation of current version." -ForegroundColor Yellow
        Add-Content $logFilePath$logFile "$dateLong - Old version of software found.  Initiating uninstallation of old and installation of current version."
        Install-Software($True, "{92ACF23E-DD58-4877-AF87-4BF7FD669928}")
    }
        
    #If existing version is known current version; log, then do nothing.
    If($gpVersion -contains "4.0.3-31"){
        Add-Content $logFilePath$logFile "$dateLong - Computer has latest version of client installed.  No further action taken."        
    #If existing version is unknown; log, then rename 
    } Else {
        Add-Content $logFilePath$logFile "$dateLong - Computer has rouge version of client installed (version $gpVersion).  Manual remediation is required."
        Rename-Item $logFilePath$logfile "REMEDIATION NEEDED - $computerName.txt"
        #Change the name of the computer's log file to set it apart from the others and notify that an unknown version was detected.
        $logFile = "REMEDIATION NEEDED - $computerName.txt"
    }
}
###