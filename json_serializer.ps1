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
			            $value = $value.Replace('"', '@ESCAPED_QUOTE_PLACEHOLDER@')
                        $value = "`"$value`""
                    }
                }
                Default {}
            }
            $data  = ""
            if ($keyValue)
            {
                $name = "$name".Replace('"', '@ESCAPED_QUOTE_PLACEHOLDER@')
                $data = "`"$name`": $value"
            }
            else
            {
                $data = "$value"  # .Replace('"', '\"')
            }
            $data = $data.Replace("\", "\\").Replace('@ESCAPED_QUOTE_PLACEHOLDER@', '\"')
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

    Begin
    {
		$script:stateArray = New-Object System.Collections.ArrayList
    	$script:valueState = $false
        $global:result = ""

    	function scan-characters ($c) {
    		switch -regex ($c)
    		{
    			"{" {
                    "(New-Object PSObject "
					[void]$script:stateArray.Add("d")
					$script:valueState=$false
                }
    			"}" {
                    ")"
					$script:stateArray.RemoveAt($script:stateArray.Count-1)
                }
                "\[" {
                    [void]$script:stateArray.Add("a")
					"@("
                }
    			"\]" {
                    $script:stateArray.RemoveAt($script:stateArray.Count-1)
					")"
                }
                "," {
                    if($script:stateArray[$script:stateArray.Count-1] -eq "a") { "," }
					else {
						$script:valueState = $false
					}
    			}
    			'"' {
					if($script:stringState -eq $true -and $script:valueState -eq $false -and $script:stateArray[$script:stateArray.Count-1] -eq "d") {
                        ' | Add-Member -Passthru NoteProperty "'
                    }
                    else { '"' }
    			}

    			":" {
                    " "
					$script:valueState = $true
                }

                "[\t\r\n]" {}

                default {$c}
    		}
    	}

    	function parse($target)
    	{
            $result = ""
			$script:lastChar = $null
			$script:unicodeString = ''
			$script:stringState = $false
            $script:escapedQuote = $false
			$script:backslashCount = 0
			$arr = $target.ToCharArray()
            #Write-Host "arr: $arr"
    		ForEach($c in $arr) {
                #Write-Host "char: $c"
				if ($lastChar -eq '\')
				{
					$script:backslashCount += 1
				} else {
					$script:backslashCount = 0
				}
				if ($c -eq '"')
				{
					# If we are not in stringState, we enter it now.
					# If we are in stringState, we make sure this quote is not escaped by backslash.
					# If it is escaped, we enter stringState again.
					$script:stringState = !$script:stringState
					#Write-Host "String State: $script:stringState"
					# Now see if this is escaped quote or end of string quote.
					if ($script:backslashCount -and $script:backslashCount % 2 -eq 1)
					{
						$script:stringState = !$script:stringState
                        $script:escapedQuote = $true
						#Write-Host "Change String State due to escaped quote: $script:stringState"
					}
				}
				if ($script:stringState)
				{
                    if ($c -eq '"')
                    {
                        if (!$script:escapedQuote)
                        {
                            $result += scan-characters $c
                        }
                        else
                        {
                            $script:unicodeString = $script:unicodeString -replace ".$", '`"'
                            #$script:unicodeString += '@ESCAPED_QUOTE_PLACEHOLDER@'  # $c
                            $script:escapedQuote = $false
                        }
                    }
                    else
                    {
                        $script:unicodeString += $c
                    }
				}
				else
				{
					#Write-Host "non-string char: $c"
					if ($script:unicodeString)
					{
                        $convertedString = convertUnicodeChars
                        #Write-Host "convertedString: $convertedString"
						$result += $convertedString
					}
					$result += scan-characters $c
				}
				$script:lastChar = $c
    		}

    		$result
    	}

		function convertUnicodeChars {
			$newString = ''
			#$unicodeChar = ''
            $duringSlashes = $false
			$appendingChars = $false
			foreach ($char in $script:unicodeString.toCharArray()){
				if ($char -eq '\')
				{
                    $duringSlashes = $true
					if ($appendingChars)
					{
                         #if slash in the middle of appendingChars, append previous accumulation, and reset
					     $newString += $unicodeChar
                         $appendingChars = $false
					}
					$newString += '\'					
				}
				else{
					if ($duringSlashes){
						$duringSlashes = $false
						if (($newString.Length -ge 1) -and ($newString.Substring($newString.Length - 1, 1) -eq '\')){
							#start accumulating in $unicodeChar if $newString has at least 1 slash at the end
							$appendingChars = $true
							$unicodeChar = ''
						}
					}

					if ($appendingChars)
					{
						$unicodeChar += $char
						if ($unicodeChar.Length -eq 5)
						{
							$unicodeCharMatch = '\' + $unicodeChar
							if ($unicodeCharMatch -cmatch "(\\u[0-9a-fA-F]{4})")
							{
								try
								{
									$unicodeCharMatch = [regex]::Unescape($unicodeCharMatch)
									#Write-Host "Converted unicodeCharMatch: $unicodeCharMatch"
									#remove last 1 slash from newString, before appending the converted 6 chars
									$newString = $newString.Substring(0, $newString.Length - 1)
									$newString += $unicodeCharMatch
								}
								catch {}
								$appendingChars = $false
							}
							else{
								#no match : just append the 4 chars accumulated in $unicodeChar to $newString
								$newString += $unicodeChar
								$appendingChars = $false
							}
						}
					}
					else
					{
						$newString += $char
					}
                }
			}

            #handle the rest if exists : if during appendingChars, $unicodeChar.Length never reached 4
            if ($appendingChars){
                $newString += $unicodeChar
            }


			# When we see backslash in string '\' we assume a unicode special character is coming.
			# We aggregate string until length of 6 is achieved.
			# We make sure candidates contain only a-f,0-9 letters.
			# We call [regex]::Unescape with try-catch on these potential unicode strings.
			# We add the converted unicode character to string result.

			$script:unicodeString = ''
			$newString
		}
    }

    Process {
        if($_) {
            # We use temp var in order to replace backslashes only after parsing,
            # such that we can differentiate between escape backslashes and regular backslashes.
            $temp = parse $_.Replace("true", '$true').Replace("false", '$false')
            #Write-Host "temp: $temp"
            $result += $temp.Replace("\\", "\").Replace('@ESCAPED_QUOTE_PLACEHOLDER@', '`"')
        }
    }

    End {
        If($json) {
            $result = parse $json
        }

        #Write-Host "result: $result"
        $result = $result | Invoke-Expression
		$result = ConvertPSObjectToHashtable $result
		$result
    }
}

function ConvertPSObjectToHashtable
{
    param (
        $InputObject
    )

    process
    {
        if ($null -eq $InputObject) { return $null }

        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string])
        {
            $collection = @(
                foreach ($object in $InputObject) { ConvertPSObjectToHashtable $object }
            )
			# The comma here is important, because when the list is empty it is converted to $null.
			# The comma solves it.
			,$collection
        }
        elseif ($InputObject.GetType().Name -eq "PSCustomObject")
        {
            $hash = @{}

            foreach ($property in $InputObject.PSObject.Properties)
            {
                $hash[$property.Name] = ConvertPSObjectToHashtable $property.Value
            }

			$hash
        }
        else
        {
            $InputObject
        }
    }
}
