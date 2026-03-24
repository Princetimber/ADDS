<#
    This file is intentionally left empty. It is must be left here for the module
    manifest to refer to. It is recreated during the build process.
  #>

# ============================================================================
# MODULE DEFAULT PARAMETER VALUES
# ============================================================================
$PSDefaultParameterValues = @{
   'Invoke-ADDSForest:DatabasePath'           = "$env:SYSTEMDRIVE\Windows"
   'Invoke-ADDSForest:LogPath'                = "$env:SYSTEMDRIVE\Windows\NTDS\"
   'Invoke-ADDSForest:SYSVOLPATH'             = "$env:SYSTEMDRIVE\Windows"
   'Invoke-ADDSDomainController:SiteName'     = 'Default-First-Site-Name'
   'Invoke-ADDSDomainController:DatabasePath' = "$env:SYSTEMDRIVE\Windows"
   'Invoke-ADDSDomainController:LogPath'      = "$env:SYSTEMDRIVE\Windows\NTDS\"
   'Invoke-ADDSDomainController:SYSVOLPath'   = "$env:SYSTEMDRIVE\Windows"
}

# dot-Source Private functions
$PrivateFunctions = Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -Recurse
foreach ($function in $PrivateFunctions) {
   try {
      . $function.FullName
   } catch {
      Write-Warning "Failed to dot-source private function file: $($function.FullName). Error: $($_.Exception.Message)"
   }
}

# dot-Source Public functions
$PublicFunctions = Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -Recurse
foreach ($function in $PublicFunctions) {
   try {
      . $function.FullName
      Export-ModuleMember -Function $function.BaseName
   } catch {
      Write-Warning "Failed to dot-source public function file: $($function.FullName). Error: $($_.Exception.Message)"
   }
}
