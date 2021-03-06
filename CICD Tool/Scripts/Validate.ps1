﻿  Param(
    [Parameter(Mandatory=$True)]
    [PSObject] 
    $vm,

    [Parameter(Mandatory=$True)]
    [String] $targetLocation,

    [Parameter(Mandatory=$true)]
    [PSObject] 
    $SrcContext,

    [Parameter(Mandatory=$true)]
    [PSObject] 
    $DestContext  

  )

  ##Parameter Type Check
  if ( $vm -ne $null )
  {
    if ( $vm.GetType().FullName -ne "Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine" )
    {
      Throw "-vm : parameter type is invalid. Please input the right parameter type: Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine." 
    }
  }

  if ( $SrcContext -ne $null )
  {
    if ( $SrcContext.GetType().FullName -ne "Microsoft.Azure.Commands.Profile.Models.PSAzureContext" )
    {
      Throw "-SrcContext : parameter type is invalid. Please input the right parameter type: Microsoft.Azure.Commands.Profile.Models.PSAzureContext."
    }
  }

  if ( $DestContext -ne $null )
  {
    if ( $DestContext.GetType().FullName -ne "Microsoft.Azure.Commands.Profile.Models.PSAzureContext" )
    {
      Throw "-DestContext : parameter type is invalid. Please input the right parameter type: Microsoft.Azure.Commands.Profile.Models.PSAzureContext"
    }
  }

  ##PS Module Check
  Check-AzureRmMigrationPSRequirement

  ####Write Progress####

  Write-Progress -id 0 -activity ($vm.Name + "(ResourceGroup:" + $vm.ResourceGroupName + ")" ) -status "Validating" -percentComplete 0
  Write-Progress -id 40 -parentId 0 -activity "Validation" -status "Started" -percentComplete 0


  Class ResourceProfile
  {
    [String] $ResourceType
    [String] $SourceResourceGroup
    [String] $DestinationResourceGroup
    [String] $SourceName
    [String] $DestinationName
  }

  Function Add-ResourceList
  {
    Param(
      [Parameter(Mandatory=$True)]
      [String] $resourceId
    )
    
    $resource = New-Object ResourceProfile
    $resource.SourceName = $resourceId.Split("/")[8]
    $resource.ResourceType = $resourceId.Split("/")[7]
    $resource.SourceResourceGroup = $resourceId.Split("/")[4]
   
    $resourceCheck = $vmResources | Where-Object { $_ -eq $resource }
   
    if ( $resourceCheck -eq $null )
    {
      $Script:vmResources += $resource
    }
  }

  Function Add-StorageList
  {
    Param(
      [Parameter(Mandatory=$True)]
      [String] $storName   
    )

    $storCheck = $vmResources | Where-Object { ($_.Name -eq $storName) -and ($_.ResourceType -eq "storageAccounts" ) }

    if ( $storCheck -eq $null )
    {
      $targetStor = Get-AzureRmStorageAccount | Where-Object { $_.StorageAccountName -eq $storName }
      
      $resource = New-Object ResourceProfile
      $resource.SourceName = $targetStor.StorageAccountName
      $resource.ResourceType = "storageAccounts"
      $resource.SourceResourceGroup = $targetStor.ResourceGroupName

      $Script:vmResources += $resource
    }
  }

  ####Get VM Components####
  Set-AzureRmContext -Context $SrcContext | Out-Null

  #VM
  $Script:vmResources = @()

  Add-ResourceList -resourceId $vm.Id

  #AS
  if ($vm.AvailabilitySetReference -ne $null)
  {
    Add-ResourceList -resourceId $vm.AvailabilitySetReference.Id
  }
   

  #NIC
  if ($vm.NetworkInterfaceIDs -ne $null)
  { 
    foreach ( $nicId in $vm.NetworkInterfaceIDs )
    {
      Add-ResourceList -resourceId $nicId
            
      $nic = Get-AzureRmNetworkInterface | Where-Object { $_.Id -eq $nicId }
     
      foreach ( $ipConfig in $nic.IpConfigurations )
      {
         #LB
         foreach( $lbp in $ipConfig.LoadBalancerBackendAddressPools)
         {   
            Add-ResourceList -resourceId $lbp.Id
            
            #PIP-LB
            $lb = Get-AzureRmLoadBalancer -Name $lbp.Id.Split("/")[8] -ResourceGroupName $lbp.Id.Split("/")[4]
                                  
            foreach ( $fip in $lb.FrontendIpConfigurations )
            {
               Add-ResourceList -resourceId $fip.PublicIpAddress.Id
            }  
         }

         #VN
         
         Add-ResourceList -resourceId $ipConfig.Subnet.Id

         #NSG-VN
         $vn = Get-AzureRmVirtualNetwork -Name $ipConfig.Subnet.Id.Split("/")[8] -ResourceGroupName $ipConfig.Subnet.Id.Split("/")[4]
            
         foreach ( $subnet in $vn.Subnets)
         {
            if ( $subnet.NetworkSecurityGroup -ne $null)
            {
              Add-ResourceList -resourceId $subnet.NetworkSecurityGroup.Id                
            }
         }
         

         #PIP-nic
         if ($ipConfig.PublicIpAddress -ne $null)
         {
           Add-ResourceList -resourceId $ipConfig.PublicIpAddress.Id
         }
      }
     
      #NSG-nic
      if ($nic.NetworkSecurityGroup -ne $null)
      {
         Add-ResourceList -resourceId $nic.NetworkSecurityGroup.Id
      }

    }
  }

  #OSDisk
  $osuri = $vm.StorageProfile.OsDisk.Vhd.Uri
  if ( $osuri -match "https" ) {
  $osstorname = $osuri.Substring(8, $osuri.IndexOf(".blob") - 8)}
  else {
    $osstorname = $osuri.Substring(7, $osuri.IndexOf(".blob") - 7)
  }
  Add-StorageList -storName $osstorname


  #DataDisk
  foreach($dataDisk in $vm.StorageProfile.DataDisks)
  {
    $datauri = $dataDisk.Vhd.Uri
    if ( $datauri -match "https" ) {
    $datastorname = $datauri.Substring(8, $datauri.IndexOf(".blob") - 8)}
    else {
      $datastorname = $datauri.Substring(7, $datauri.IndexOf(".blob") - 7)
    }
    Add-StorageList -storName $datastorname
  } 


  ####Start Validation####


  Enum ResultType
  {
    Failed = 0
    Succeed = 1
    SucceedWithWarning = 2
  }

  Function Add-ResultList
  {
    Param(
      [Parameter(Mandatory=$True)]
      [ResultType] $result,
      [Parameter(Mandatory=$False)]
      [String] $detail
    )
    
    $messageHeader = $null
    switch($result){
        "Failed"{
            $Script:result = "Failed"
            $messageHeader = "[Error] "
        }
        "SucceedWithWarning"{
            if($Script:result -eq "Succeed"){
                $Script:result = "SucceedWithWarning"
            }
            $messageHeader = "[Warning] "
        }
    }
    if($detail){
        $Script:resultDetailsList += $messageHeader + $detail
    }
  }

  Function Get-AzureRmVmCoreFamily
  {
    Param(
      [Parameter(Mandatory=$True)]
      [String] $VmSize   
    )

    switch -regex ($VmSize) 
    { 
        "^Basic_A[0-4]$" {"Basic A Family Cores"} 
        "^Standard_A[0-7]$" {"Standard A0-A7 Family Cores"}
        "^Standard_A([89]|1[01])$" {"Standard A8-A11 Family Cores"} 
        "^Standard_D1?[1-5]_v2$" {"Standard Dv2 Family Cores "} 
        "^Standard_D1?[1-4]$" {"Standard D Family Cores"} 
        "^Standard_G[1-5]$" {"Standard G Family Cores"} 
        "^Standard_DS1?[1-4]$" {"Standard DS Family Cores"} 
        "^Standard_DS1?[1-5]_v2$" {"Standard DSv2 Family Cores"} 
        "^Standard_GS[1-5]$" {"Standard GS Family Cores"} 
        "^Standard_F([1248]|16)$" {"Standard F Family Cores"} 
        "^Standard_F([1248]|16)s$" {"Standard FS Family Cores"} 
        "^Standard_NV(6|12|24)$" {"Standard NV Family Cores"} 
        "^Standard_NC(6|12|24)$" {"Standard NC Family Cores"} 
        "^Standard_H(8m?|16m?r?)$" {"Standard H Family Cores"} 
        default {"The Core Family could not be determined."}
    }
  }

  #Define Validation Result and Message
  $Script:result = "Succeed"
  $Script:resultDetailsList = @()

  # check src permission
  Write-Progress -id 40 -parentId 0 -activity "Validation" -status "Checking Permission" -percentComplete 10

  Set-AzureRmContext -Context $SrcContext | Out-Null
  $roleAssignment = Get-AzureRmRoleAssignment -IncludeClassicAdministrators -SignInName $SrcContext.Account

  if(!($roleAssignment.RoleDefinitionName -eq "CoAdministrator" -or $roleAssignment.RoleDefinitionName -eq "Owner")) 
  {
    Add-ResultList -result "Failed" -detail "The current user don't have source subscription permission, because the user is not owner or coAdmin."
  }


  # check dest permission
  Set-AzureRmContext -Context $DestContext | Out-Null
  $roleAssignment = Get-AzureRmRoleAssignment -IncludeClassicAdministrators -SignInName $DestContext.Account

  if(!($roleAssignment.RoleDefinitionName -eq "CoAdministrator" -or $roleAssignment.RoleDefinitionName -eq "Owner")) 
  {
    Add-ResultList -result "Failed" -detail "The current user don't have source subscription permission, because the user is not owner or coAdmin."
  }


  # Core Quota Check
  Write-Progress -id 40 -parentId 0 -activity "Validation" -status "Checking Quota" -percentComplete 30
  Set-AzureRmContext -Context $DestContext | Out-Null

  $vmHardwareProfile = Get-AzureRmVmSize -Location $targetLocation | Where-Object{$_.Name -eq $vm.HardwareProfile.VmSize}
  $vmCoreNumber = $vmHardwareProfile.NumberOfCores

  $vmCoreFamily = Get-AzureRmVmCoreFamily -VmSize $vm.HardwareProfile.VmSize

  $vmUsage = Get-AzureRmVMUsage -Location $targetLocation
  $vmTotalCoreUsage = $vmUsage | Where-Object{$_.Name.LocalizedValue -eq "Total Regional Cores"}
  $vmFamilyCoreUsage = $vmUsage | Where-Object{$_.Name.LocalizedValue -eq $vmCoreFamily}

  $vmAvailableTotalCore = $vmTotalCoreUsage.Limit - $vmTotalCoreUsage.CurrentValue
  $vmAvailableFamilyCoreUsage = $vmFamilyCoreUsage.Limit - $vmFamilyCoreUsage.CurrentValue

  if($vmCoreNumber -gt $vmAvailableTotalCore) 
  {
    Add-ResultList -result "Failed" -detail ("The vm core quota validate failed, because destination subscription does not have enough regional quota. Current quota left: " + $vmAvailableTotalCore + ". VM required: " + $vmCoreNumber + "." )
  }


  if($vmCoreNumber -gt $vmAvailableFamilyCoreUsage) 
  {
    Add-ResultList -result "Failed" -detail ("The vm core quota validate failed, because destination subscription does not have enough " + $vmCoreFamily + " quota. Current quota left: " + $vmAvailableFamilyCoreUsage + ". VM required: " + $vmCoreNumber + "." )
  }


  # Storage Quota Check
  $storageAccountsCount = 0
  foreach ($resource in $vmResources) {
    if($resource.ResourceType -eq "storageAccounts"){
        $storageAccountsCount += 1
    }
  }
  $storageUsage = Get-AzureRmStorageUsage
  $storageAvailable = $storageUsage.Limit - $storageUsage.CurrentValue

  if($storageAccountsCount -gt $storageAvailable)
  {
    Add-ResultList -result "Failed" -detail ("The storage account quota validate failed, because destination subscription does not have enough storage account quota. Current quota left: " + $storageAvailable + ". VM required: " + $storageAccountsCount + "." )
  }


  # Storage Name Existence
  Write-Progress -id 40 -parentId 0 -activity "Validation" -status "Checking Name Availability" -percentComplete 50
  $storageAccountNames = @()
  foreach ( $resource in $vmResources)
  {
    if($resource.ResourceType -eq "storageAccounts")
    {
       $saCheck = $storageAccountNames | Where-Object { $_ -eq $resource.SourceName }
       if ( $saCheck -eq $null )
       {
           $storageAccountNames += $resource.SourceName
       }
    }
  }

  Set-AzureRmContext -Context $DestContext | Out-Null
  Foreach ($storage in $storageAccountNames)
  {
    $storageCheck = Get-AzureRmStorageAccount | Where-Object { $_.StorageAccountName -eq $storage}

    if ( $storageCheck -eq $null )
    {
      $storageAvailability = Get-AzureRmStorageAccountNameAvailability -Name $storage
      if ($storageAvailability.NameAvailable -eq $false)
      {
        Add-ResultList -result "Failed" -detail ("The storage account " + $storage + " validate failed, because " + $storageAvailability.Reason)
      }

    }
    else
    {
        Add-ResultList -result "SucceedWithWarning" -detail ("storage account name: " + $storage + " exist in the subscription")
    }
  }

  ## Check DNS Name Availability

  foreach ( $resource in $vmResources)
  {
    if($resource.ResourceType -eq "publicIPAddresses"){
        Set-AzureRmContext -Context $SrcContext | Out-Null
        $sourcePublicAddress = Get-AzureRmPublicIpAddress -Name $resource.SourceName -ResourceGroupName $resource.SourceResourceGroup
        Set-AzureRmContext -Context $DestContext | Out-Null
        if($sourcePublicAddress.DnsSettings.DomainNameLabel -ne $null)
        {
            $dnsTestResult = Test-AzureRmDnsAvailability -DomainNameLabel $sourcePublicAddress.DnsSettings.DomainNameLabel -Location $targetLocation
            if($dnsTestResult -ne "True")
            {
                Add-ResultList -result "Failed" -detail ("The dns name " + $sourcePublicAddress.DnsSettings.DomainNameLabel + " validate failed, because DNS name not available in target location.")
            }
        }
    }
  }

  ##Check Resource Existence
  Write-Progress -id 40 -parentId 0 -activity "Validation" -status "Checking Resource Existence" -percentComplete 70
  Set-AzureRmContext -Context $DestContext | Out-Null

  $DestResources = Get-AzureRmResource 

  foreach ( $resource in $vmResources)
  {
    $resourceCheck = $DestResources | Where-Object {$_.ResourceType -match $resource.ResourceType } | 
                                      Where-Object {$_.ResourceId.Split("/")[4] -eq $resource.SourceResourceGroup} | 
                                      Where-Object {$_.Name -eq $resource.SourceName}
    if ($resourceCheck -ne $null)
    {
        switch ($resource.ResourceType) 
        { 
            "virtualMachines" {$resourceResult = "Failed"} 
            "availabilitySets" {$resourceResult = "Failed"}
            "networkInterfaces" {$resourceResult = "Failed"}
            "loadBalancers" {$resourceResult = "SucceedWithWarning"}
            "publicIPAddresses" {$resourceResult = "SucceedWithWarning"}
            "virtualNetworks" {$resourceResult = "SucceedWithWarning"}
            "networkSecurityGroups" {$resourceResult = "SucceedWithWarning"}
            "storageAccounts" {$resourceResult = "SucceedWithWarning"}
        }
        Add-ResultList -result $resourceResult -detail ("The resource:" + $resource.SourceName +  " (type: "+$resource.ResourceType+") in Resource Group: " + $resource.SourceResourceGroup + " already exists in destination.")
    }
    


  }

  Write-Progress -id 40 -parentId 0 -activity "Validation" -status "Complete" -percentComplete 100

  $validationResult = New-Object PSObject
  $validationResult | Add-Member -MemberType NoteProperty -Name ValidationResult -Value $Script:result
  $validationResult | Add-Member -MemberType NoteProperty -Name Messages -Value $Script:resultDetailsList

  return $validationResult