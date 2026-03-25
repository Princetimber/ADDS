<#
    Root module bootstrapper for Invoke-ADDS.
    It establishes module defaults, dot-sources private and public functions,
    and exports the public surface during import/build.
#>

# ============================================================================
# MODULE DEFAULT PARAMETER VALUES
# ============================================================================
$PSDefaultParameterValues = @{
   'Invoke-ADDSForest:DatabasePath'           = "$env:SYSTEMDRIVE\Windows"
   'Invoke-ADDSForest:LogPath'                = "$env:SYSTEMDRIVE\Windows\NTDS\"
   'Invoke-ADDSForest:SysvolPath'             = "$env:SYSTEMDRIVE\Windows"
   'Invoke-ADDomainController:SiteName'       = 'Default-First-Site-Name'
   'Invoke-ADDomainController:DatabasePath'   = "$env:SYSTEMDRIVE\Windows"
   'Invoke-ADDomainController:LogPath'        = "$env:SYSTEMDRIVE\Windows\NTDS\"
   'Invoke-ADDomainController:SysvolPath'     = "$env:SYSTEMDRIVE\Windows"
}

# dot-Source Private functions
$PrivateFunctions = Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -Recurse
foreach ($function in $PrivateFunctions) {
   try {
      . $function.FullName
   } catch {
      throw "Failed to import private function file '$($function.FullName)': $($_.Exception.Message)"
   }
}

# dot-Source Public functions
$PublicFunctions = Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -Recurse
foreach ($function in $PublicFunctions) {
   try {
      . $function.FullName
      Export-ModuleMember -Function $function.BaseName
   } catch {
      throw "Failed to import public function file '$($function.FullName)': $($_.Exception.Message)"
   }
}
