#Requires -Version 7.0

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:ModuleRoot = Join-Path $script:RepoRoot 'powershell' 'Modules' 'RevealUI.RevStation'
    Import-Module (Join-Path $script:ModuleRoot 'RevealUI.RevStation.psd1') -Force 6> $null
}

AfterAll {
    Remove-Module RevealUI.RevStation -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertFrom-RevvaultJson' {
    It 'returns the value from a success payload' {
        InModuleScope RevealUI.RevStation {
            ConvertFrom-RevvaultJson '{"path":"creds/api","value":"s3cr3t-val"}'
        } | Should -Be 's3cr3t-val'
    }

    It 'preserves a full multi-line value (JSON-escaped newlines)' {
        $result = InModuleScope RevealUI.RevStation {
            ConvertFrom-RevvaultJson '{"path":"creds/pem","value":"line1\nline2\nline3"}'
        }
        $result | Should -Be "line1`nline2`nline3"
    }

    It 'throws the revvault error message on an error payload' {
        {
            InModuleScope RevealUI.RevStation {
                ConvertFrom-RevvaultJson '{"error":"secret not found: creds/missing"}'
            }
        } | Should -Throw -ExpectedMessage '*secret not found*'
    }

    It 'throws on empty output' {
        { InModuleScope RevealUI.RevStation { ConvertFrom-RevvaultJson '' } } |
            Should -Throw -ExpectedMessage '*no output*'
    }

    It 'throws on non-JSON output (e.g. a shell error leaking through)' {
        { InModuleScope RevealUI.RevStation { ConvertFrom-RevvaultJson 'revvault: command not found' } } |
            Should -Throw -ExpectedMessage '*non-JSON*'
    }

    It 'throws when JSON has neither value nor error' {
        { InModuleScope RevealUI.RevStation { ConvertFrom-RevvaultJson '{"path":"creds/api"}' } } |
            Should -Throw -ExpectedMessage '*neither*'
    }
}
