#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot '..\src\Install-Fonts.ps1')

    # Real font files are copied from the system fonts folder, so none are committed
    $fontsSource = Join-Path $env:SystemRoot 'Fonts'
}

Describe 'ConvertTo-NormalizedFolderPath' {
    It 'repairs a drive root mangled by -File argument parsing' {
        ConvertTo-NormalizedFolderPath 'E:"' | Should -Be 'E:\'
    }

    It 'leaves a normal folder path unchanged' {
        ConvertTo-NormalizedFolderPath 'C:\Some Folder\Fonts' | Should -Be 'C:\Some Folder\Fonts'
    }
}

Describe 'Get-FontFiles' {
    BeforeAll {
        $folder = Join-Path $TestDrive 'My [Fonts] Folder'
        New-Item -ItemType Directory -Path $folder | Out-Null
        Copy-Item (Join-Path $fontsSource 'arial.ttf') (Join-Path $folder 'arial.ttf')
        Copy-Item (Join-Path $fontsSource 'arialbd.ttf') (Join-Path $folder 'UPPER.TTF')
        Set-Content -LiteralPath (Join-Path $folder 'fake.otf') -Value 'x'
        Set-Content -LiteralPath (Join-Path $folder 'readme.txt') -Value 'x'
        Set-Content -LiteralPath (Join-Path $folder 'old.fon') -Value 'x'

        $sub = Join-Path $folder 'sub'
        New-Item -ItemType Directory -Path $sub | Out-Null
        Copy-Item (Join-Path $fontsSource 'arial.ttf') (Join-Path $sub 'nested.ttf')

        $names = (Get-FontFiles $folder).Name
    }

    It 'finds .ttf and .otf files regardless of extension case' {
        $names | Should -Be @('arial.ttf', 'fake.otf', 'UPPER.TTF')
    }

    It 'ignores subfolders' {
        $names | Should -Not -Contain 'nested.ttf'
    }

    It 'returns an empty array for a folder without fonts' {
        $empty = Join-Path $TestDrive 'empty'
        New-Item -ItemType Directory -Path $empty | Out-Null
        @(Get-FontFiles $empty).Count | Should -Be 0
    }
}

Describe 'Get-FontDisplayName' {
    It 'omits the Regular face' {
        Get-FontDisplayName (Join-Path $fontsSource 'arial.ttf') | Should -Be 'Arial (TrueType)'
    }

    It 'includes a non-Regular face' {
        Get-FontDisplayName (Join-Path $fontsSource 'arialbd.ttf') | Should -Be 'Arial Bold (TrueType)'
    }

    It 'throws for a file that is not a font' {
        $bogus = Join-Path $TestDrive 'corrupt.ttf'
        [System.IO.File]::WriteAllBytes($bogus, [byte[]](1..200))
        { Get-FontDisplayName $bogus } | Should -Throw
    }
}

Describe 'Test-FontInstalled' {
    It 'detects a system font' {
        Test-FontInstalled -DisplayName 'Arial (TrueType)' -FileName 'arial.ttf' | Should -BeTrue
    }

    It 'returns false for an unknown font' {
        $random = [guid]::NewGuid().ToString('N')
        Test-FontInstalled -DisplayName "$random (TrueType)" -FileName "$random.ttf" | Should -BeFalse
    }
}

Describe 'Install-Fonts' {
    It 'reports invalid files as failed and installed fonts as skipped' {
        $folder = Join-Path $TestDrive 'mixed'
        New-Item -ItemType Directory -Path $folder | Out-Null
        Copy-Item (Join-Path $fontsSource 'arial.ttf') (Join-Path $folder 'arial.ttf')
        [System.IO.File]::WriteAllBytes((Join-Path $folder 'corrupt.ttf'), [byte[]](1..200))

        $result = Install-Fonts -Files (Get-FontFiles $folder)

        $result.Installed.Count | Should -Be 0
        $result.Skipped | Should -Be @('arial.ttf')
        $result.Failed | Should -Be @('corrupt.ttf: not a valid font file')
    }
}

Describe 'Format-Summary' {
    It 'lists only non-empty sections' {
        $result = [pscustomobject]@{
            Installed = @('a.ttf')
            Skipped   = @()
            Failed    = @('b.ttf: not a valid font file')
        }
        $summary = Format-Summary $result
        $summary | Should -Match 'Installed: 1'
        $summary | Should -Match 'Failed: 1'
        $summary | Should -Not -Match 'Skipped'
    }

    It 'truncates long lists' {
        $result = [pscustomobject]@{
            Installed = @(1..20 | ForEach-Object { "font$_.ttf" })
            Skipped   = @()
            Failed    = @()
        }
        Format-Summary $result | Should -Match '\.\.\. and 5 more'
    }
}
