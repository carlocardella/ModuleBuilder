Describe "MoveUsingStatements" {

    Context "Necessary Parameters" {
        $CommandInfo = InModuleScope ModuleBuilder { Get-Command MoveUsingStatements }

        It 'has a mandatory AST parameter' {
            $AST = $CommandInfo.Parameters['AST']
            $AST | Should -Not -BeNullOrEmpty
            $AST.ParameterType | Should -Be ([System.Management.Automation.Language.Ast])
            $AST.Attributes.Where{ $_ -is [Parameter] }.Mandatory | Should -Be $true
        }

        It "has an optional string Encoding parameter" {
            $Encoding = $CommandInfo.Parameters['Encoding']
            $Encoding | Should -Not -BeNullOrEmpty
            $Encoding.ParameterType | Should -Be ([String])
            $Encoding.Attributes.Where{$_ -is [Parameter]}.Mandatory | Should -Be $False
        }
    }

    Context "Moving Using Statements to the beginning of the file" {

        $MoveUsingStatementsCmd = InModuleScope ModuleBuilder {
            $null = Mock Write-Warning { }
            {   param($RootModule)
                ConvertToAst $RootModule | MoveUsingStatements
            }
        }

        $TestCases = @(
            @{
                TestCaseName = 'Move all using statements in `n terminated files to the top'
                PSM1File     = "function x {`n}`n" +
                "using namespace System.IO`n`n" + #UsingMustBeAtStartOfScript
                "function y {`n}`n" +
                "using namespace System.Drawing" #UsingMustBeAtStartOfScript
                ErrorBefore  = 2
                ErrorAfter   = 0
            },
            @{
                TestCaseName = 'Move all using statements in `r`n terminated files to the top'
                PSM1File     = "function x {`r`n}`r`n" +
                "USING namespace System.IO`r`n`r`n" + #UsingMustBeAtStartOfScript
                "function y {`r`n}`r`n" +
                "USING namespace System.Drawing" #UsingMustBeAtStartOfScript
                ErrorBefore  = 2
                ErrorAfter   = 0
            },
            @{
                TestCaseName = 'Not change the content again if there are no out-of-place using statements'
                PSM1File     = "using namespace System.IO`r`n`r`n" +
                "using namespace System.Drawing`r`n" +
                "function x { `r`n}`r`n" +
                "function y { `r`n}`r`n"
                ErrorBefore  = 0
                ErrorAfter   = 0
            },
            @{
                TestCaseName = 'Not move anything if there are (other) parse errors'
                PSM1File     = "using namespace System.IO`r`n`r`n" +
                "function x { `r`n}`r`n" +
                "using namespace System.Drawing`r`n" + # UsingMustBeAtStartOfScript
                "function y { `r`n}`r`n}" # Extra } at the end
                ErrorBefore  = 2
                ErrorAfter   = 2
            }
        )

        It 'It should <TestCaseName>' -TestCases $TestCases {
            param($TestCaseName, $PSM1File, $ErrorBefore, $ErrorAfter)

            $testModuleFile = "$TestDrive/MyModule.psm1"
            Set-Content $testModuleFile -value $PSM1File -Encoding UTF8
            # Before
            $ErrorFound = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $testModuleFile,
                [ref]$null,
                [ref]$ErrorFound
            )
            $ErrorFound.Count | Should -Be $ErrorBefore

            # After
            &$MoveUsingStatementsCmd -RootModule $testModuleFile

            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $testModuleFile,
                [ref]$null,
                [ref]$ErrorFound
            )
            $ErrorFound.Count | Should -Be $ErrorAfter
        }
    }
    Context "When MoveUsingStatements should do nothing" {

        $MoveUsingStatementsCmd = InModuleScope ModuleBuilder {
            $null = Mock Write-Warning {}
            $null = Mock Set-Content {}
            $null = Mock Write-Debug {} -ParameterFilter {$Message -eq "No Using Statement Error found." }

            {   param($RootModule)
                ConvertToAst $RootModule | MoveUsingStatements
            }
        }

        It 'Should Warn and skip when there are Parsing errors other than Using Statements' {
            $testModuleFile = "$TestDrive/MyModule.psm1"
            $PSM1File = "Using namespace System.IO`r`n function xyz {}`r`n}`r`nUsing namespace System.Drawing" # extra }                Set-Content $testModuleFile -value $PSM1File -Encoding UTF8
            Set-Content $testModuleFile -value $PSM1File -Encoding UTF8

            &$MoveUsingStatementsCmd -RootModule $testModuleFile
            Assert-MockCalled -CommandName Write-Warning -Times 1 -ModuleName ModuleBuilder
            Assert-MockCalled -CommandName Set-Content -Times 0 -ModuleName ModuleBuilder
        }

        It 'Should not do anything when there are no Using Statements Errors' {

            $testModuleFile = "$TestDrive\MyModule.psm1"
            $PSM1File = "Using namespace System.IO; function x {}"
            Set-Content $testModuleFile -value $PSM1File -Encoding UTF8

            &$MoveUsingStatementsCmd -RootModule $testModuleFile

            Assert-MockCalled -CommandName Write-Debug -Times 1 -ModuleName ModuleBuilder
            Assert-MockCalled -CommandName Set-Content -Times 0 -ModuleName ModuleBuilder
            (Get-Content -Raw $testModuleFile).Trim() | Should -Be $PSM1File

        }


        It 'Should not modify file when introducing parsing errors' {

            $testModuleFile = "$TestDrive\MyModule.psm1"
            $PSM1File = "function x {}`r`nUsing namespace System.IO;"
            Set-Content $testModuleFile -value $PSM1File -Encoding UTF8

            InModuleScope ModuleBuilder {
                $null = Mock New-Object {
                    # Introducing Parsing Error in the file
                    $Flag = [System.Collections.ArrayList]::new()
                    $null = $Flag.Add("MyParsingError}")
                    $PSCmdlet.WriteObject($Flag, $false)
                }
            }

            &$MoveUsingStatementsCmd -RootModule $testModuleFile

            Assert-MockCalled -CommandName Set-Content -Times 0 -ModuleName ModuleBuilder
            Assert-MockCalled -CommandName Write-Warning -Times 1 -ModuleName ModuleBuilder
            (Get-Content -Raw $testModuleFile).Trim() | Should -Be $PSM1File

        }
    }
}
