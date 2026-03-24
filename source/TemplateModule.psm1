<#
    Development-time module loader. During development, this file dot-sources all
    .ps1 files from Private/ and Public/ so you can import the module directly.

    At build time, Sampler/ModuleBuilder compiles a different .psm1 into the
    output folder that inlines all function definitions into a single file.
    Do not add runtime logic here that you expect to survive the build.
#>


   # dot-Source Private functions
 $PrivateFunctions = Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -Recurse
 foreach ($function in $PrivateFunctions) {
     try {
        . $function.FullName
     }
     catch {
        Write-Warning "Failed to dot-source private function file: $($function.FullName). Error: $($_.Exception.Message)"
     }
 }

   # dot-Source Public functions
 $PublicFunctions = Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -Recurse
 foreach ($function in $PublicFunctions) {
     try {
        . $function.FullName
        Export-ModuleMember -Function $function.BaseName
     }
     catch {
        Write-Warning "Failed to dot-source public function file: $($function.FullName). Error: $($_.Exception.Message)"
     }
 }
