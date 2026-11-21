@{
    Path                     = 'xDPsApiExplorer.psd1'
    OutputDirectory          = '..\output\xDPsApiExplorer'
    VersionedOutputDirectory = $true
    CopyPaths                = @(
        'Data'
        '..\README.md'
        '..\LICENSE'
    )
    SourceDirectories        = @(
        'Private'
        'Public'
    )
    PublicFilter             = @(
        'Public\*.ps1'
    )
    Prefix                   = 'prefix.ps1'
    Encoding                 = 'UTF8'
}
