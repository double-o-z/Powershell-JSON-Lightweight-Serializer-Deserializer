# Powershell-JSON-Lightweight-Serializer-Deserializer
Simple powershell functions to convert from and to json. Very lightweight, will be supported with every powershell version. No dependences.
NB: Can convert any json to object. Still not ready to handle complex powershell objects. So, if you convert from json first, you're good. If you try to convert to json an object you've built instead of converting from json with this serializer, than it might fail.

# Example usage:

$JSON = Get-Content .\data.json -Encoding utf8

# Convert from json to powershell object (Deserialize):
$a = $JSON | ConvertFrom-JSON-Stable

$a[0].prop += 1

# Convert from powershell object to json (Serialize):
$b = $JSON | ConvertTo-JSON-Stable

Set-Content -Path .\data.json -Value $b -Encoding utf8
