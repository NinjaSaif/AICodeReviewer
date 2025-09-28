param(
    [string]$currentFolder = "."
)

$ollamaServer = "http://localhost:11434"
$codingFileExtensions = @("*.py", "*.js", "*.java", "*.cpp", "*.html", "*.css", "*.php")

function Invoke-ScanFiles {
    Get-ChildItem -Path $currentFolder -Recurse -Include $codingFileExtensions
}

function Invoke-CodeDocumentation {
    $mdFiles = Get-ChildItem -Path $currentFolder -Recurse -Include "*.md"
    $mdFiles | Where-Object { 
        $_.Name -ne "README.md" -and 
        $_.Name -notlike "*review_*" -and
        $_.FullName -notlike "*\node_modules\*" -and
        $_.FullName -notlike "*\bin\*" -and
        $_.FullName -notlike "*\obj\*"
    }
}

function Send-OllamaMessage {
    param (
        [string]$modelName = "qwen2:1.5b",
        [string]$codeStrings,
        [string]$docs
    )
    
    $apiEndpoint = "$ollamaServer/api/generate"
    
    if ($docs -and $codeStrings) {
        $promptText = "Review the following coding files as one project, Read the documentation: $docs `n`n and answer any comments inside it: `n`n$codeStrings"
    }
    elseif ($docs) {
        $promptText = "Review the following documentation: $docs"
    }
    else {
        $promptText = "Review the following code: $codeStrings"
    }
    
    $requestBody = @{
        model  = $modelName
        prompt = $promptText
        stream = $false
    } | ConvertTo-Json -Depth 10 -Compress
    
    try {
        Write-Host "Sending request to Ollama..." -ForegroundColor Cyan
        $response = Invoke-RestMethod -Uri $apiEndpoint -Method Post -Body $requestBody -ContentType "application/json; charset=utf-8"
        return $response.response
    }
    catch {
        $errorDetails = $_.ErrorDetails.Message
        Write-Host "Error communicating with Ollama: $($_.Exception.Message)" -ForegroundColor Red
        if ($errorDetails) {
            Write-Host "Server response: $errorDetails" -ForegroundColor Red
        }
        return $null
    }
}

function Invoke-CodeReview {
    Write-Host "Starting code review process..." -ForegroundColor Green
    Write-Host "Current folder: $currentFolder" -ForegroundColor Yellow
    
    $docs = Invoke-CodeDocumentation
    Write-Host "Found $($docs.Count) documentation files" -ForegroundColor Cyan

    $files = Invoke-ScanFiles
    Write-Host "Found $($files.Count) code files" -ForegroundColor Cyan
    
    foreach ($document in $docs) {
        Write-Host "Reading documentation: $($document.Name)" -ForegroundColor Green
        $content = Get-Content $document.FullName -Raw
        $review = Send-OllamaMessage -docs $content
        
        if (-not $review) {
            Write-Host "No response from Ollama for $($document.Name)" -ForegroundColor Red
            continue
        }
        
        Write-Host "Documentation review for $($document.Name):" -ForegroundColor Yellow
        Write-Host $review
        
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($document.Name)
        $createFile = Join-Path $currentFolder "reading_$baseName.md"
        
        $counter = 1
        while (Test-Path $createFile) {
            Write-Host "$createFile already exists" -ForegroundColor Yellow
            $createFile = Join-Path $currentFolder "reading_$baseName($counter).md"
            $counter++
        }
        
        $review | Out-File -FilePath $createFile -Encoding UTF8
        Write-Host "Saved review to: $createFile" -ForegroundColor Green
    }
    
    foreach ($file in $files) {
        Write-Host "Reviewing code: $($file.Name)" -ForegroundColor Green
        $content = Get-Content $file.FullName -Raw
        $review = Send-OllamaMessage -codeStrings $content
        
        if (-not $review) {
            Write-Host "No response from Ollama for $($file.Name)" -ForegroundColor Red
            continue
        }
        
        Write-Host "Code review for $($file.Name):" -ForegroundColor Yellow
        Write-Host $review
        
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $createFile = Join-Path $currentFolder "review_$baseName.md"
        
        $counter = 1
        while (Test-Path $createFile) {
            Write-Host "$createFile already exists" -ForegroundColor Yellow
            $createFile = Join-Path $currentFolder "review_$baseName($counter).md"
            $counter++
        }
        
        $review | Out-File -FilePath $createFile -Encoding UTF8
        Write-Host "Saved review to: $createFile" -ForegroundColor Green
    }
    
    Write-Host "Code review process completed!" -ForegroundColor Green
}

try {
    $testResponse = Invoke-RestMethod -Uri "$ollamaServer/api/tags" -Method Get -TimeoutSec 5
    Write-Host "Connected to Ollama server successfully" -ForegroundColor Green
    Write-Host "Test response: $testResponse"
    Invoke-CodeReview
}
catch {
    Write-Host "Cannot connect to Ollama server at $ollamaServer" -ForegroundColor Red
    Write-Host "Please ensure Ollama is running and accessible" -ForegroundColor Yellow
}
