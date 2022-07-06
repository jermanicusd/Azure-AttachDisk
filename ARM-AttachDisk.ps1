#Create and Attach disk to Azure VM#
Write-Host "Script last tested 2-17-16 by J.D." -ForegroundColor Green
Write-Host "Planned updates - Premium Storage" -ForegroundColor Green

Import-Module 'C:\Program Files (x86)\Microsoft SDKs\Azure\PowerShell\ServiceManagement\Azure\Azure.psd1'

if (!($cred)) {$cred = Get-Credential}
Add-AzureAccount -Credential $cred

write-host "#------------Script for adding drives to Azure VMs-------------#" -ForegroundColor Magenta

$vmname = Read-Host "Please enter name of VM to add disk to"
$cloudservice = Read-Host "Please enter the Cloud Service name"
$WinRMURi = Get-AzureWinRMUri -ServiceName $cloudservice -Name $VMName | Select-Object -ExpandProperty AbsoluteUri
Write-Host "Current Storage Accounts Used:" -Fore Yellow
$sourceVm =Get-AzureVM -ServiceName $CloudService -Name $vmname 
$sourceVM.VM.OSVirtualHardDisk.Medialink.Host
$sourceVM.VM.DataVirtualHardDisks.Medialink.Host

#----Creates the disk in the blob and attaches it to the vm----#
function CreateDisk
{

    Set-Variable -Name disklabel -Scope Global -Value (Read-Host "Please enter the name of this new disk") 

    [int]$xMenu1 = 0
    while ( $xMenu1 -lt 1 -or $xMenu1 -gt 5 ){
    #Write-Host "`n`tAzure VM deployment script 1.0`n" -ForegroundColor Magenta
    Write-host "`t`tSelect Storage Account type:`n" -Fore Cyan
    Write-host "`t`t1. Geo Replicated Storage (6 copies) - MHSAGeo01" -Fore Cyan
    Write-host "`t`t2. Geo Replicated Storage (6 copies) - MHSAGeo02" -Fore Cyan
    Write-host "`t`t3. Zone Storage (3 copies) - MHSAZone01" -Fore Cyan
    Write-host "`t`t4. Local Storage (1 copy) - MHSALocal01" -Fore Cyan
    Write-host "`t`t5. Quit and exit" -Fore Cyan
    [Int]$xMenu1 = read-host "Please enter an option 1 to 5..." }
    Switch( $xMenu1 ){
        1{$staccount = "https://mhsageo01.blob.core.windows.net/vhds/$cloudservice-$vmname-$disklabel.vhd"}
        2{$staccount = "https://mhsageo02.blob.core.windows.net/vhds/$cloudservice-$vmname-$disklabel.vhd"}
        3{$staccount = "https://MHSAZone01.blob.core.windows.net/vhds/$cloudservice-$vmname-$disklabel.vhd"}
        4{$staccount = "https://MHSALocal01.blob.core.windows.net/vhds/$cloudservice-$vmname-$disklabel.vhd"}
        5{exit-pssession}
    default{$staccount = "MHSAGeo01"}
    }

    $Luns = Get-azurevm -ServiceName $cloudservice -Name $vmname | Get-AzureDataDisk | select -ExpandProperty LUN
        if ($Luns)
        {  
            Write-Verbose -Message "Generating a random LUN number to be used"
            $Lun = 1..100 | where {$Luns -notcontains $_} | select -First 1
        }
        else
        {
            Write-Verbose -Message "No Data Disks found attached to VM"
            $Lun = 1
        }

    Write-Host "Creating a new 1TB disk on $vmname that is stored on $staccount" -ForegroundColor Green

    Get-AzureVM $cloudservice -Name $vmname | Add-AzureDataDisk -CreateNew -DiskSizeInGB 1023 -DiskLabel $disklabel -LUN $Lun -MediaLocation $staccount | Update-AzureVM

    $continue = Read-Host "Do you want the drive created in the OS? (Y or N)"
    if ($continue -eq "N") {keepgoing}
    else {DisktoOS}

}

#-----------------Connect to VM and finish disk provisioning--------------------#

function DisktoOS
{

    Set-Variable -Name Session -Scope Global -Value (New-PSSession -ConnectionUri $WinRMURi -Credential $Cred -Name $vmname -SessionOption (New-PSSessionOption -SkipCACheck) -ErrorAction SilentlyContinue) 

    Write-host "Invoking command to Initialize / Create / Format the new Disk added to the Azure VM" -ForegroundColor Green     

    Invoke-command -session $Session -argumentlist $diskLabel -ScriptBlock { 
            Get-Disk |
            where partitionstyle -eq 'raw' |
            where Number -NE "0" |
            where Number -NE "1" |
            Initialize-Disk -PartitionStyle GPT -PassThru |
            New-Partition -AssignDriveLetter -UseMaximumSize |
            Format-Volume -FileSystem NTFS -NewFileSystemLabel $disklabel -Confirm:$false -ErrorVariable FormatDiskError
            } 

    keepgoing

}


#-----Begining of the loop-----#
function keepgoing
{
    Set-Variable -Name MoreDisks -Scope Global -Value (Read-Host "Do you want to continue adding disks to this VM? (Y or N)")
    if ($MoreDisks -eq "Y") {CreateDisk}
    else {break;}
}

#-----Starting at the end (calling funtion)-----#
keepgoing
