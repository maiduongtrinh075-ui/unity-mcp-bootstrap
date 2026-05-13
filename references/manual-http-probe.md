# Manual HTTP Probe

Use these local routes when you need a simple ground-truth check without relying on higher-level wrappers.

## Health

```powershell
Invoke-RestMethod -Uri 'http://127.0.0.1:8080/health' -Method Get
```

## Instances

```powershell
Invoke-RestMethod -Uri 'http://127.0.0.1:8080/api/instances' -Method Get
```

## Tiny Command

Use the current Unity instance hash after it appears:

```powershell
$body = @{
  type = 'manage_editor'
  params = @{
    action = 'stop'
  }
  unity_instance = '183fee18e951e05e'
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri 'http://127.0.0.1:8080/api/command' `
  -Method Post `
  -ContentType 'application/json' `
  -Body $body
```

## Start Local HTTP Server

```powershell
Start-Process -FilePath 'C:\Users\X\.local\bin\mcp-for-unity.exe' `
  -ArgumentList '--transport','http','--http-url','http://127.0.0.1:8080' `
  -WindowStyle Hidden
```
