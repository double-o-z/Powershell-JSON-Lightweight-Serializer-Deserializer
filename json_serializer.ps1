$global:tab_index = 0
Function ConvertTo-JSON-Stable {
    Begin {
        $output = @()
    }
    Process {
		# Converts values, and key, value pairs to string representations, later to be joined into whole json.
        Function New-JSONProperty {
			param (
				[Parameter(Mandatory = $true)]
				[String]$name,
				[Parameter(Mandatory = $false)]
				$value
			)
			# If value argument exists, it means we called this function on a key, value pair.
			if ($PSBoundParameters.ContainsKey('value'))
            {
                $keyValue = $true
            }
            else
            {
                $keyValue = $false
                $value = $name
            }
			# We want to try to convert strings to boolean
			if ($value -eq "false" -or $value -eq "true")
			{
				try {$value = [System.Convert]::ToBoolean($value)} catch [FormatException] {}
			}
            $dataType = $value.GetType().Name
            switch -regex ($dataType)
            {
                "Boolean" {$value = $value.ToString().ToLower()}
                "String" {
                    if ($value -ne "null")
                    {
                        $value = "`"$value`""
                    }
                }
                Default {}
            }
            $data  = ""
            if ($keyValue)
            {
                $data = "`"$name`": $value"
            }
            else
            {
                $data = "$value"
            }
            $data = $data.Replace("\", "\\")
            $data
        }

        $targetObject = $_
		if ($targetObject -eq $null)
		{
			$null
			return
		}
		else
		{
			$jsonProperties = @()
			$shouldOutput = $true
			$isCustomObject = $false
            $isHashtable = $false
			$isList = $false
			$Type = $targetObject.GetType().Name
			if ($Type -eq "PSCustomObject") {
				$isCustomObject = $true
				$keys = $targetObject | Get-Member -MemberType *property
				$global:tab_index += 1
				$wrapper_begin = "{"
				if ($keys)
				{
					# This next part, handles indentation.
					$wrapper_begin += "`r`n"+"`t"*$global:tab_index
				}
				$delimeter = ",`r`n"+"`t"*$global:tab_index
			}
			elseif ($Type -eq "Object[]")
			{
				$isList = $true
				$keys = $targetObject
				$wrapper_begin = "["
				$wrapper_end = "]"
				$delimeter = ", "
			}
            elseif ($Type -eq "Hashtable")
			{
				$isHashtable = $true
				$keys = $targetObject.Keys
				$global:tab_index += 1
				$wrapper_begin = "{"
				if ($keys)
				{
					# This next part, handles indentation.
					$wrapper_begin += "`r`n"+"`t"*$global:tab_index
				}
				$delimeter = ",`r`n"+"`t"*$global:tab_index
			} else {
				$keys = @()
				$shouldOutput = $false
				$output += New-JSONProperty $targetObject
			}

			if ($shouldOutput)
			{
				ForEach ($key in $keys){
					if ($isCustomObject) {
						$key = $key.Name
						$value = $targetObject.$key
					}
                    elseif ($isHashtable)
					{
						$value = $targetObject.$key
					}
					elseif ($isList)
					{
						$value = $key
					}
                    else {
						$value = $null
					}
					if ($value -eq $null)
					{
						continue
					}
					$dataType = ($value.GetType()).Name
					switch -regex ($dataType) {
						# TODO: PSObject, Hashtable.
						'Object\[\]' {
							# We call ConvertTo-JSON-Stable recursively,
							# to get the string representation of this list's inner parts.
							$value = $value | ConvertTo-JSON-Stable
							$value = $value -join ", "
							if ($key -ne $value)
							{

								$jsonProperties += "`"$key`": [$value]"
							}
							else
							{
								$jsonProperties += "[$value]"
							}
						}
                        'PSCustomObject' {
						    # We call ConvertTo-JSON-Stable recursively,
							# to get the string representation of this PSCustomObject's inner parts.
							$jsonProperties += "`"$key`": $($value | ConvertTo-JSON-Stable)"
                        }
                        'Hashtable' {
						    # We call ConvertTo-JSON-Stable recursively,
							# to get the string representation of this Hashtable's inner parts.
							$jsonProperties += "`"$key`": $($value | ConvertTo-JSON-Stable)"
                        }
						default {
							if ($Type -eq "Object[]")
							{
								$jsonProperties += New-JSONProperty $key
							}
							else
							{
								$jsonProperties += New-JSONProperty $key $value
							}
						}
					}
				}
				$currentOutput = $wrapper_begin
				$currentOutput = $currentOutput + "$($jsonProperties -join $delimeter)"
				# This next part, handles indentation in the json.
				if ($Type -eq "PSCustomObject" -or $Type -eq "Hashtable") {
					$global:tab_index = $global:tab_index - 1
					$wrapper_end = "}"
					if ($keys)
					{
						$wrapper_end = "`r`n"+"`t"*$global:tab_index+$wrapper_end
					}
				}
				$currentOutput = $currentOutput + $wrapper_end
				$output += $currentOutput
			}
		}
    }
    End {
        foreach ($item in $output)
        {
            $item
        }
    }
}

Function ConvertFrom-JSON-Stable {
    param(
        $json,
        [switch]$raw
    )
    # TODO: Replace logic of convertsion from json object to powershell object. Currently we create a PSCustomObject with following syntax:
    # PsObject syntax: ** New-Object PSObject | Add-Member -Passthru NoteProperty "key1" "value2" | Add-Member -Passthru NoteProperty "key2" "value2" **
    # We should try to create a Hashtable, which is neat and simpler than PSCustomObject, with the following *possible* syntax:
    # Hashtable possible syntax: ** @{"key1"="value1";"key2"="value2"} **

    Begin
    {
        $script:stringState = $false
        $script:appendingToUnicode = $false
        $script:unicodeStringCandidate = ''
        $script:stateArray=New-Object System.Collections.ArrayList
        $script:valueState = $false
        $global:result=""

        function scan-characters ($c) {
			$script:out = ''
            switch -regex ($c)
            {
                "{" {
					if ($script:appendingToUnicode)
					{
						$script:appendingToUnicode = $false
						if ($script:stringState)
						{
							$script:out += $script:unicodeStringCandidate
						}
						else
						{
							$script:unicodeStringCandidate
						}
						$script:unicodeStringCandidate = ''
					}
                    if ($script:stringState)
                    {
                        $script:out += $c
                    }
                    else
                    {
                        $script:out += "(New-Object PSObject "
                        [void]$script:stateArray.Add("d")
                        $script:valueState=$script:stringState=$false
                    }
                }
                "}" {
					if ($script:appendingToUnicode)
					{
						$script:appendingToUnicode = $false
						if ($script:stringState)
						{
							$script:out += $script:unicodeStringCandidate
						}
						else
						{
							$script:unicodeStringCandidate
						}
						$script:unicodeStringCandidate = ''
					}
                    if ($script:stringState)
                    {
                        $script:out += $c
                    }
                    else
                    {
                        $script:out += ")"
                        $script:stateArray.RemoveAt($script:stateArray.Count-1)
                    }
                }
                "\[" {
					if ($script:appendingToUnicode)
					{
						$script:appendingToUnicode = $false
						if ($script:stringState)
						{
							$script:out += $script:unicodeStringCandidate
						}
						else
						{
							$script:unicodeStringCandidate
						}
						$script:unicodeStringCandidate = ''
					}
                    if ($script:stringState)
                    {
                        $script:out += $c
                    }
                    else
                    {
                        [void]$script:stateArray.Add("a")
                        $script:out += "@("
                    }
                }
                "\]" {
					if ($script:appendingToUnicode)
					{
						$script:appendingToUnicode = $false
						if ($script:stringState)
						{
							$script:out += $script:unicodeStringCandidate
						}
						else
						{
							$script:unicodeStringCandidate
						}
						$script:unicodeStringCandidate = ''
					}
                    if ($script:stringState)
                    {
                        $script:out += $c
                    }
                    else
                    {
                        $script:stateArray.RemoveAt($script:stateArray.Count-1)
                        $script:out += ")"
                    }
                }
                "," {
					if ($script:appendingToUnicode)
					{
						$script:appendingToUnicode = $false
						if ($script:stringState)
						{
							$script:out += $script:unicodeStringCandidate
						}
						else
						{
							$script:unicodeStringCandidate
						}
						$script:unicodeStringCandidate = ''
					}
                    if ($script:stringState)
                    {
                        $script:out += $c
                    }
                    else
                    {
                        if($script:stateArray[$script:stateArray.Count-1] -eq "a") { $script:out += "," }
                        else {
                            $script:valueState = $false
                            #$script:stringState = $false
                        }
                    }
                }
                '"' {
					if ($script:appendingToUnicode)
					{
						$script:appendingToUnicode = $false
						if ($script:stringState)
						{
							$script:out += $script:unicodeStringCandidate
						}
						else
						{
							$script:unicodeStringCandidate
						}
						$script:unicodeStringCandidate = ''
					}
                    if($script:stringState -eq $false -and $script:valueState -eq $false -and $script:stateArray[$script:stateArray.Count-1] -eq "d") {
                        #' | Add-Member -Passthru NoteProperty $([regex]::Unescape("'
                        $script:out += ' | Add-Member -Passthru NoteProperty "'
                    }
                    else {
                        #Write-Host "script:stringState: $script:stringState"
                        #Write-Host "script:valueState: $script:valueState"
                        #Write-Host "script:stateArray: $script:stateArray"
                        if ($script:valueState -eq $false)
                        {
                            #'"))'
                            $script:out += '"'
                        }
                        else
                        {
                            if (!$script:stringState)
                            {
                                #'$([regex]::Unescape("'
                                $script:out += '"'
                            }
                            else
                            {
                                #'"))'
                                $script:out += '"'
                            }
                        }
                    }
                    $script:stringState = !$script:stringState
                }

                ":" {
					if ($script:appendingToUnicode)
					{
						$script:appendingToUnicode = $false
						if ($script:stringState)
						{
							$script:out += $script:unicodeStringCandidate
						}
						else
						{
							$script:unicodeStringCandidate
						}
						$script:unicodeStringCandidate = ''
					}
                    if($script:stringState){
                        $script:out += ":"
                    } else {
                        $script:out += " "
                        $script:valueState = $true
                    }
                }

                "[\t\r\n]" {
					if ($script:appendingToUnicode)
					{
						$script:appendingToUnicode = $false
						if ($script:stringState)
						{
							$script:out += $script:unicodeStringCandidate
						}
						else
						{
							$script:unicodeStringCandidate
						}
						$script:unicodeStringCandidate = ''
					}
				}

                default {
                    #Write-Host "c: $c"
                    if ($c -eq '\'){
                        if ($script:appendingToUnicode)
                        {
                            $script:out += $c
                        }
                        $script:unicodeStringCandidate = $c
                        $script:appendingToUnicode = $true
                    }
                    elseif ($script:appendingToUnicode){
                        $script:unicodeStringCandidate += $c
                    } else {
                        $script:out += $c
                    }
					if ($script:unicodeStringCandidate.Length -eq 6)
                    {
                        if ($script:unicodeStringCandidate.startswith("\u") -and ($script:unicodeStringCandidate.split("\").count -eq 2))
                        {
                            try {
                                #Write-Host "Converting unicode candidate: $script:unicodeStringCandidate"
                                $script:unicodeStringCandidate = [regex]::Unescape($script:unicodeStringCandidate)
                                #Write-Host "Converted unicode to: $script:unicodeStringCandidate"
                            }
                            catch {
                                #Write-Host "Failed converting candidate: $script:unicodeStringCandidate."
                            }
                        }
                        $script:out += $script:unicodeStringCandidate
                        $script:unicodeStringCandidate = ''
                        $script:appendingToUnicode = $false
                    }
                }
            }
			if ($script:out){
				$script:out
			}
        }

        function parse($target)
        {
            $result = ""
            $firstBackslash = $true
            ForEach($c in $target.ToCharArray()) {
                $result += scan-characters $c
            }

            $result
        }
    }

    Process {
        if($_) {
            $result += parse $_.Replace("true", '$true').Replace("false", '$false').Replace("\\", "\")
        }
    }

    End {
        If($json) {
            $result = parse $json
        }
        #Write-Host "result: $result"
        If(-Not $raw) {
            $result | Invoke-Expression
        } else {
            $result
        }
    }
}
