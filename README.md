# Powershell-JSON-Lightweight-Serializer-Deserializer
Simple powershell functions to convert from and to json. Very lightweight, will be supported with every powershell version. No dependencies.
Can convert any json data to powershell data structure. 


# Example usage:

$JSON = Get-Content .\data.json -Encoding utf8

# Convert from json to powershell data structure (Deserialize):
$a = $JSON | ConvertFrom-JSON-Stable
$a.GetType().Name
# Hashtable

$a[0].prop += 1

# Convert from powershell data structure to json (Serialize):
$b = $a | ConvertTo-JSON-Stable

Set-Content -Path .\data.json -Value $b -Encoding utf8
