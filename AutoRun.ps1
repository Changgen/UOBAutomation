Get-ExecutionPolicy
Set-ExecutionPolicy RemoteSigned

#----------------------------------------Settings----------------------------------------
$GIT_REPOSITORY_NAME = "test-samples"  #Input github repository name
$GIT_REPOSITORY_URL = "https://github.com/bitbar/${GIT_REPOSITORY_NAME}.git"  #Change as needed
$TD_CLOUD_BASE_URL = "https://cloud.bitbar.com"
$TD_TOKEN_URL = "${TD_CLOUD_BASE_URL}/oauth/token"
$TD_PROJECTS_URL = "${TD_CLOUD_BASE_URL}/api/me/projects"
$TD_FILES_URL = "${TD_CLOUD_BASE_URL}/api/me/files"
$TD_RUN_TEST_URL = "${TD_CLOUD_BASE_URL}/api/me/runs"
$TD_USER_DEVICE_GROUPS_URL = "${TD_CLOUD_BASE_URL}/api/me/device-groups?limit=0"
$TD_USER_FRAMEWORKS_URL = "${TD_CLOUD_BASE_URL}/api/me/available-frameworks?limit=0"
$TD_TEST_RUNS_URL_TEMPLATE = "${TD_CLOUD_BASE_URL}/api/me/projects/<projectId>/runs"
$TD_TEST_RUN_ITEM_URL_TEMPLATE = "${TD_TEST_RUNS_URL_TEMPLATE}/<runId>"
$TD_TEST_DEVICE_SESSION_URL_TEMPLATE = "${TD_TEST_RUN_ITEM_URL_TEMPLATE}/device-sessions"
$TD_TEST_RUN_ITEM_BROWSER_URL_TEMPLATE = "${TD_CLOUD_BASE_URL}/#testing/test-run/<projectId>/<runId>"
$TD_DEFAULT_HEADER = "Accept: application/json"
$TOKEN_TMP_FILE = "token.json"
$TD_USER = "20PRuolyUwEnEsbF2xGH2fmYA0ZjGu9I"  #input bitbar cloud user account if authenticate with access token, input API Key if authenticate with API Key
$API_KEY = "20PRuolyUwEnEsbF2xGH2fmYA0ZjGu9I"  #not used
$PASSWORD = ""  #input bitbar cloud user account password if authenticate with access token, leave blank if authenticate with API Key
$CURL_SLIENT = " -s "
$PROJECT_NAME = "UOBAutomation"  #input project name
$TEST_RUN_NAME = "UITest"  #input test run name
$EXCUTION_CONTEXT = "Server" #Server/Client
$FRAMEWORK = "Appium"   #Appium/XCTest/XCUITest/Flutter/Instrumention
$FRAMEWORK_ID = 0   #Obsolete
$DEVICE_GROUP_ID = 4127  #Device ID has higher priority than device group id, set to $null if device group is not applied.
$DEVICE_IDS = $null  #array, e.g. 4450,21218,21235; set to $null if not use device ID
$APP_FOLDER = "app"
$TEST_FOLDER = "test"
$TEST_RESULTS_FOLDER = "results"
$TEST_SCREENSHOTS_FOLDER = "screenshots"
$OS_TYPE = "no-set"
$TIMEOUT = 6000
$SCHEDULER = "PARALLEL"
$RESULT_LIMIT = 0
$CONNECTION_FAILURES_LIMIT = 20
$DEBUG = "N"


#************************************Private Function*************************************
#-------------------Pre-request-------------------
function SystemSetup()
{
    if (!(Get-Command jq)) {
        InstallJq
    }
}

function InstallJq()
{
    Set-ExecutionPolicy RemoteSigned -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    chocolatey install jq
}

#-----------------Common Utilities-----------------
function GetFullPath()
{
    param(
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $folder
    )

    $cdPath = Split-Path -Parent $MyInvocation.PSCommandPath
    $fullPath = Join-Path $cdPath $folder

    Write-Host "[Debug] - The full path:"$fullPath
    
    return $fullPath
}

function ZipTestScriptFiles()
{
    $path = GetFullPath $TEST_FOLDER

    Write-Host "[Info] - Zipping test scripts..."

    Compress-Archive -Path $path\* -DestinationPath $path".zip"

    Write-Host -ForegroundColor Green "[Info] - Test script has been zipped=>"$path".zip"
    Remove-Item -Path $path -Recurse
    Write-Host -ForegroundColor Darkyellow "[Info] - Test script has been removed=>"$path
}

function DownloadAppPackage()
{
}

function ConvertToJson()
{
    param(
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $jsonPath
    )

    Write-Host "[Debug] - JSON Path=>"$jsonPath
    $json = Get-Content -Path $jsonPath | ConvertFrom-Json

    $json | ConvertTo-Json -Depth 32 | Set-Content -Path $jsonPath
}

#------------Test Pre/Post Proccessing------------
function Initilization()
{
    $tokenFilePath = GetFullPath("${TOKEN_TMP_FILE}")

    if (Test-Path "${tokenFilePath}"){
        Remove-Item "${tokenFilePath}"
    }

    Verbose
}

#------------------Git Automation------------------
function PullScriptsFromGit()
{
    $gitRepositoryDir = GetFullPath ${GIT_REPOSITORY_NAME}
    $scriptDir = GetFullPath ${TEST_FOLDER}

    Write-Host "[Info] - Pull test scripts from git to loacal=> Repository:$GIT_REPOSITORY_URL, Destination:$scriptDir"
    git clone $GIT_REPOSITORY_URL

    Copy-Item -Path $gitRepositoryDir -Destination $scriptDir -Recurse
    Remove-Item -Path $gitRepositoryDir -Recurse
}

#-----------------bitbar Cloud API-----------------
function Verbose()
{
    if ($DEBUG -eq "N") {$CURL_SLIENT = ""}
}

function Authenticate() {
    $jsonPath = GetFullPath("${TOKEN_TMP_FILE}")
    $authCurlData = "client_id=testdroid-cloud-api&grant_type=password&username=${TD_USER}"
    $authCurlData = "${authCurlData}&password=${PASSWORD}"

    curl.exe ${CURL_SILENT} -X POST -H "${TD_DEFAULT_HEADER}" -d "${authCurlData}" $TD_TOKEN_URL | jq > "${jsonPath}"
    ConvertToJson $jsonPath

    $authError = $(jq '.error_description' "${TOKEN_TMP_FILE}")

    if ($authError -ne "null") {
        Write-Host -ForegroundColor Red "[Error] - Fail to log in, Please check credentials!=>"$authError
    } else {
        $accessToken = $(jq '.access_token' "${TOKEN_TMP_FILE}")
        Write-Host -ForegroundColor Green "[Info] - Log in sccessed!=> Access Token:"$accessToken
    }
}

function GetToken() {
    $jsonPath = GetFullPath("${TOKEN_TMP_FILE}")

    if (!(Test-Path "${jsonPath}")) {Authenticate}

    $accessToken = $(jq -r '.access_token' $TOKEN_TMP_FILE)
    $refreshToken = $(jq -r '.refresh_token' $TOKEN_TMP_FILE)
    
    $tokenExpiresDateTime = (Get-Date).AddSeconds($(jq -r '.expires_in' $TOKEN_TMP_FILE)/2)

    if ($(Get-Date) -gt $tokenExpiresDateTime) {
        Write-Host -ForegroundColor Yellow "[Warning] - Token will expired at $tokenExpiresDateTime, refresh token..."
        $refreshAuthCurlData = "client_id=testdroid-cloud-api&grant_type=refresh_token&refresh_token=${refreshToken}"
        curl.exe ${CURL_SILENT} -X POST -H "${TD_DEFAULT_HEADER}" -d "${refreshAuthCurlData}" $TD_TOKEN_URL > "${jsonPath}"

        ConvertToJson $jsonPath

        $accessToken = $(jq -r '.access_token' $TOKEN_TMP_FILE)
        $refreshToken = $(jq -r '.refresh_token' $TOKEN_TMP_FILE)
        if ($accessToken -eq "null") {
            Write-Host -ForegroundColor Red "[Error] - Bad access token, Please check credentials!=>"$accessToken
        }
    }

    if ($accessToken -eq "null") {
        Write-Host -ForegroundColor Red "[Error] - Bad access token, Please check credentials!=>"$accessToken
    }
    
    Write-Host "[Info] - Access token:"$accessToken
    return $accessToken
}

function AuthCurl() {
    param(
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$true)]
        $url
    )

    if ($PASSWORD -ne "") {
        Write-Host "[Info] - Authentication with access token!"
        $projectListingHeader = "Authorization: Bearer $(GetToken)"

        Write-Host  "[Debug] - curl.exe" ${CURL_SILENT} -H "'${TD_DEFAULT_HEADER}'" -H """${projectListingHeader}""" ${url}
        curl.exe ${CURL_SILENT} -H "'${TD_DEFAULT_HEADER}'" -H """${projectListingHeader}""" ${url}
    } else {
        Write-Host "[Info] - Authentication with API Key!"

        Write-Host "[Debug] - curl.exe" ${CURL_SILENT} -H """${TD_DEFAULT_HEADER}""" -u ${TD_USER}: ${url}
        curl.exe ${CURL_SILENT} -H "'${TD_DEFAULT_HEADER}'" -u ${TD_USER}":" ${url}
    }
}

function GetProjectId()
{
    param(
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $projectName
    )

    $projectId = $(AuthCurl ${TD_PROJECTS_URL}?filter=name_eq_${projectName} | jq .data[0].id)

    if ($projectId -ne "null") {
        Write-Host -ForegroundColor Green "[Info] - Project founded!=> Name:"$projectName", Id: "$projectId
    } else {
        Write-Host -ForegroundColor Green "[Info] - Project not found!=> Name:"$projectName", Id: "$projectId
    }
    
    return $projectId
}

function CreateProject()
{
    param(
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $projectName
    )

    $projectId = GetProjectId $projectName

    if ($projectId -ne "null") {
        Write-Host -ForegroundColor Darkyellow "[Info] - Remove existing project=> Name:"$projectName", Id: "$projectId
        RemoveProject $projectId
    }

    $projectId = $((AuthCurl -X POST "${TD_PROJECTS_URL}" --data name=${projectName}) | jq .id)
    Write-Host -ForegroundColor Green "[Success] - Created project=> Name:"$projectName", Id: "$projectId

    return $projectId
}

function RemoveProject()
{
    param(
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $projectId
    )

    AuthCurl -X DELETE ${TD_PROJECTS_URL}"/"$projectId

    Write-Host -ForegroundColor Darkyellow "[Info] - Removed project:"$projectId     
}

function UrlFromTemplate()
{
    param(
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $urlTemplate,
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $projectId,
        [Parameter(Mandatory=$false,ValueFromRemainingArguments=$false)]
        $testRunId
    )

    $url = $($urlTemplate -replace "<projectId>", ${projectId})
    $url = $($url -replace "<runId>", ${testRunId})

    Write-Host "[Info] - Actual URL:"$url

    return $url
}

function UploadAppPackagesToCloud()
{
    Write-Host "[Info] - Uploading app package..."
    $appFileId = UploadFilesToCloud $APP_FOLDER

    Write-Host "[Info] - App File ID:"$appFileId

    return $appFileId 
}


function UploadTestScriptsToCloud()
{
    Write-Host "[Info] - Uploading test scripts..."
    $scriptFileId = UploadFilesToCloud $TEST_FOLDER

    Write-Host "[Info] - Script File ID:"$scriptFileId
    return $scriptFileId
}

function UploadFilesToCloud()
{
    param(
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $folder
    )

    $folderPath = GetFullPath($folder)

    $files = Get-ChildItem $folderPath -Recurse

    foreach ($file in $files)
    {
        $response = $(AuthCurl -X POST ${TD_FILES_URL} -F "file=@$folderPath/$file")
        $fileUploadId = $(echo "$response" | jq '.id')
    
        if ($fileUploadId) {
            Write-Host -ForegroundColor Green "[Success] - File have beed uploaded to cloud=> File:"$file", Id:"$fileUploadId
            return $fileUploadId
        } else {
            Write-Host -ForegroundColor Red "[Error] - Fail to upload file!=> File:"$file
        }
    }
}

function GetOSType()
{
    $osType = $null
    $appPath = GetFullPath($APP_FOLDER)

    $files = Get-ChildItem $appPath -Recurse

    foreach ($file in $files)
    {
        $extension = [System.IO.Path]::GetExtension($file)

        if ($extension -eq ".ipa") 
        {
            $osType = "IOS"
        } elseif ($extension -eq ".apk") 
        {
            $osType = "ANDROID"
        } else 
        {
            $osType = $null
        }
    }

    if ([string]::IsNullOrEmpty($osType)){
        Write-Host -ForegroundColor Red "[Error] - OS Type is not supported! Check app package=> Folder:"$appPath", File:"$file
    } else {
        Write-Host -ForegroundColor Green "[Info] - OS Type is"$osType
    }
    
    $OS_TYPE = $osType

    return $osType
}

function GetFrameworkId()
{
    $frameworkId = $null
    $osType = GetOSType

    if ($osType -eq "IOS"){
        if ($FRAMEWORK -eq "Appium"){
            if ($EXCUTION_CONTEXT -eq "Server"){
                $frameworkId = 542
            } elseif ($EXCUTION_CONTEXT -eq "Client"){
                $frameworkId = $null
            } else {
                Write-Host -ForegroundColor Red "[Error] - Server or Client? need to be defined for Appium"
            }
        } elseif ($FRAMEWORK -eq "XCTest") {
            $frameworkId = 590
        } elseif ($FRAMEWORK -eq "XCUITest") {
            $frameworkId = 612
        } elseif ($FRAMEWORK -eq "Flutter") {
            $frameworkId = 840
        } else {
            Write-Host -ForegroundColor Red "[Error] - Framework not supported!=>$FRAMEWORK"
        }
    } elseif ($osType -eq "ANDROID"){
        if ($FRAMEWORK -eq "Appium"){
            if ($EXCUTION_CONTEXT -eq "Server"){
                $frameworkId = 541
            } elseif ($EXCUTION_CONTEXT -eq "Client"){
                $frameworkId = $null
            } else {
                Write-Host -ForegroundColor Red "[Error] - Server or Client? need to be defined for Appium"
            }
        } elseif ($FRAMEWORK -eq "Instrumention") {
            $frameworkId = 252
        } else {
            Write-Host -ForegroundColor Red "[Error] - Framework not supported!=>$FRAMEWORK"
        }
    } else {
    }

    $FRAMEWORK_ID = $frameworkId
    return $frameworkId
}

function StartTestRun()
{
    param(
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $projectId,
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $appFileId,
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $scriptFileId
    )

    $osType = GetOSType
    $frameworkId = GetFrameworkId

    $jsonPath = GetFullPath("config.json")
    Write-Host "[Debug] - JSON Path=>"$jsonPath
    $config = Get-Content -Path $jsonPath | ConvertFrom-Json

    $config.projectId = $projectId
    $config.testRunName = $TEST_RUN_NAME
    $config.osType = $osType
    $config.frameworkId = $frameworkId
    $config.files[0].id = $appFileId
    $config.files[1].id = $scriptFileId
    $config.deviceGroupId = $DEVICE_GROUP_ID
    $config.timeout = $TIMEOUT
    $config.deviceId = $DEVICE_IDS

    $config | ConvertTo-Json -Depth 100 | Set-Content -Path "$jsonPath"
    Write-Host -ForegroundColor Green "[Info] - JSON Config=>"$config

    if ($PASSWORD -ne "") {
        $projectListingHeader = "Authorization: Bearer $(GetToken)"
        $response = $(curl.exe -H "${TD_DEFAULT_HEADER}" -H 'Content-Type: application/json' -H "${projectListingHeader}" ${TD_RUN_TEST_URL} --data-binary "@${jsonPath}")
    } else {
        $response = $(curl.exe -H 'Content-Type: application/json' -u ${TD_USER}":" ${TD_RUN_TEST_URL} --data-binary "@${jsonPath}")
    }

    #$response = $(AuthCurl -H "'Content-Type: application/json'" "${TD_RUN_TEST_URL}" --data-binary "@${jsonPath}")
    $testRunId = $response | jq .id

    if ($testRunId -eq "null") {
        Write-Host -ForegroundColor Red "[Error] - Fail to create test run!=> HTTP response:"$response
    } else {
        Write-Host -ForegroundColor Green "[Info] - Test Run started! Test Run ID:"$testRunId
        return $testRunId
    }
}

function GetTestRunResults()
{
    param(
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $projectId,
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $testRunId
    )
    $jsonPath = GetFullPath("${TOKEN_TMP_FILE}")

    $deviceRunsUrl = $(UrlFromTemplate "${TD_TEST_DEVICE_SESSION_URL_TEMPLATE}" ${projectId} ${testRunId})
    $response = $(AuthCurl "${deviceRunsUrl}")
    $deviceCount = $($response | jq '.total')
    Write-Host -ForegroundColor Green "[Info] - Device count for test:"${deviceCount}

    $testRunStatusTmpFile = "status.json"
    $jsonPath = GetFullPath("${testRunStatusTmpFile}")
    $testRunUrl = $(UrlFromTemplate "${TD_TEST_RUN_ITEM_URL_TEMPLATE}" ${projectId} ${testRunId})
    $testRunBrowserUrl = $(UrlFromTemplate "${TD_TEST_RUN_ITEM_BROWSER_URL_TEMPLATE}" ${projectId} ${testRunId})
    Write-Host -ForegroundColor Green "[Info] - Results are to be found at ${testRunBrowserUrl}"

    $testStatus = ""
    $connectionFailures = 0
    $fetchStatus = 0

    while ($fetchStatus -lt 1){
        Start-Sleep -s 10

        AuthCurl "${testRunUrl}" > "${jsonPath}"
        ConvertToJson $jsonPath
        $testStatusNew = $(jq -r '.state' $jsonPath)
        if (${testStatus} -ne ${testStatusNew}){
            $testStatus = $testStatusNew
            Write-Host -ForegroundColor Green  "[Info] - Test status changed: $testStatus"
        }

        switch ($testStatus)
        {
            "FINISHED" {
                Write-Host -ForegroundColor Green  "[Success] - Test execution finished!=> Project ID:"$projectId", Test Run ID:"$testRunId
                $(GetResultFiles $projectId $testRunId)
                Write-Host -ForegroundColor Green  "[Success] - Fetch test results finished!=> Project ID:"$projectId", Test Run ID:"$testRunId
                $fetchStatus = 1
                break
            }

            ("WAITING" -or "RUNNING") {
                Write-Host -ForegroundColor Red  "[Info] - Test run is now running..."
                break
            }

            "null" {
                $connectionFailures = $connectionFailures + 1

                if ($connectionFailures -gt $CONNECTION_FAILURES_LIMIT) {
                    Write-Host -ForegroundColor Red  "[Error] - cannot read test status, connection problem? (fail ["$connection_failures"/"$CONNECTION_FAILURES_LIMIT"]"
                    $fetchStatus = 1
                    break
                }
            }
        }
    }
}

function GetDeviceName()
{
    param(
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $projectId,
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $testRunId,
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $deviceSessionId
    )

    $deviceInfoJson = $(GetDeviceInfoJson $projectId $testRunId $deviceSessionId)

    $deviceName = $($deviceInfoJson | jq -r '.device.displayName')

    Write-Host -ForegroundColor Green "[Info] - Device Name:"$deviceName", Device session ID: "$deviceSessionId
    return $deviceName
}

function GetDeviceInfoJson()
{
    param(
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $projectId,
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $testRunId,
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $deviceSessionId
    )

    $testRunItemUrl = $(UrlfromTemplate "${TD_TEST_RUN_ITEM_URL_TEMPLATE}" ${projectId} ${testRunId})
    $deviceInfoUrl = "${testRunItemUrl}/device-sessions/${deviceSessionId}"
    $deviceInfoJson = $(AuthCurl ${deviceInfoUrl} --fail)

    #Write-Host "[Info] - Device Information JSON:"$deviceInfoJson
    return $deviceInfoJson
}

function WasDeviceExcluded()
{
    param(
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $projectId,
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $testRunId,
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $deviceSessionId
    )

    $deviceInfoJson = $(GetDeviceInfoJson $projectId $testRunId $deviceSessionId)
    $deviceStatus = $($deviceInfoJson | jq -r '.state')

    Write-Host -ForegroundColor Green "[Info] - Status of device:"$deviceStatus", Device session ID: "$deviceSessionId

    if ($deviceStauts -eq "EXCLUDED") {
        Write-Host "[Info] - Device was excluded from Test Run, Test Run ID:"$testRunId", Device Session ID: "$deviceSessionId
        return 1
    } else {
        Write-Host "[Info] - Device was included from Test Run, Test Run ID:"$testRunId", Device Session ID: "$deviceSessionId
        return 0
    }
}

function GetDeviceResultFiles()
{
    param(
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $projectId,
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $testRunId,
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $deviceSessionId,
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $deviceName
    )

    $testResultsDir = GetFullPath("${TEST_RESULTS_FOLDER}")

    if (Test-Path “${testResultsDir}/${deviceName}"){Remove-Item -Path “${testResultsDir}/${deviceName}” -Recurse}
    mkdir “${testResultsDir}/${deviceName}”
    Write-Host -ForegroundColor Green "[Info] - Downloading test result files and store to folder=>"${testResultsDir}/${deviceName}

    $testRunItemUrl = $(UrlFromTemplate "${TD_TEST_RUN_ITEM_URL_TEMPLATE}" $projectId ${testRunId})
    $deviceInfoUrl = "$testRunItemUrl/device-sessions/$deviceSessionId"
    $deviceSessionFilesUrl = "$testRunItemUrl/device-sessions/$deviceSessionId/output-file-set/files?limit=${RESULT_LIMIT}"
    $response = $(AuthCurl "$deviceSessionFilesUrl")

    $deviceFileIds = $($response | jq '.data[] |\"\(.id);\(.name)\"')

    Write-Host "[Debug] - Device test results files:"$($deviceFileIds | jq .)

    foreach ($fileSpecs in $deviceFileIds){
        GetDeviceResultFile "$testRunId" "$deviceSessionId" "$deviceName" "$fileSpecs"
    }
}

function GetDeviceResultFile()
{
    param(
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $testRunId,
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $deviceSessionId,
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $deviceName,
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $fileSpecs
    )

    $testResultsDir = GetFullPath("${TEST_RESULTS_FOLDER}")

    $fileSpecs = $($fileSpecs -replace """", "")
    $fileId = $($fileSpecs -split ";", "")[0]
    $fileName = $($fileSpecs -split ";", "")[1]

    $fileItemUrl = "${TD_CLOUD_BASE_URL}/api/me/files/$fileId/file"
    AuthCurl "$fileItemUrl" --fail --output "${testResultsDir}/${deviceName}/$fileName" --location
}

function GetDeviceScreenshots()
{
    param(
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $projectId,
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $testRunId,
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $deviceSessionId,
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $deviceName
    )

    $testScreenshotDir = GetFullPath("${TEST_SCREENSHOTS_FOLDER}")
    $deviceScreenshotDir = "${testScreenshotDir}/${deviceName}"

    if (Test-Path "${deviceScreenshotDir}"){Remove-Item -Path "${deviceScreenshotDir}" -Recurse}
    mkdir "${deviceScreenshotDir}"
    Write-Host -ForegroundColor Green "Downloading test screenshot files and store to folder=>"${deviceScreenshotDir}

    $testRunItemUrl = $(UrlFromTemplate "${TD_TEST_RUN_ITEM_URL_TEMPLATE}" $projectId ${testRunId})
    $deviceSessionScreenshotsUrl = "${testRunItemUrl}/device-sessions/${deviceSessionId}/screenshots"
    $response = $(AuthCurl "$deviceSessionScreenshotsUrl")

    $deviceScreenshotIds = $($response | jq '.data[] |\"\(.id);\(.originalName)\"')
    Write-Host -ForegroundColor Green "[Info] - Fetched device screentshots IDs:"$deviceScreenshotIds

    foreach ($deviceScreenshotSpecs in $deviceScreenshotIds){
        GetDeviceScreenshot $projectId $testRunId $deviceSessionId "$deviceName" "$deviceScreenshotSpecs"
    } 
}

function GetDeviceScreenshot()
{
    param(
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $projectId,
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $testRunId,
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $deviceSessionId,
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $deviceName,
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $fileSpecs
    )

    $testScreenshotDir = GetFullPath("${TEST_SCREENSHOTS_FOLDER}")

    $fileSpecs = $($fileSpecs -replace """", "")
    $fileId = $($fileSpecs -split ";", "")[0]
    $fileName = $($fileSpecs -split ";", "")[1]

    $testRunItemUrl = $(UrlFromTemplate "${TD_TEST_RUN_ITEM_URL_TEMPLATE}" $projectId ${testRunId})
    $fileItemUrl = "${testRunItemUrl}/device-sessions/${deviceSessionId}/screenshots/${fileId}"

    $response = $(AuthCurl "$fileItemUrl" --fail --output "${testScreenshotDir}/${deviceName}/${fileName}" --location)
}

function GetResultFiles()
{
    param(
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $projectId,
        [Parameter(Mandatory=$true,ValueFromRemainingArguments=$false)]
        $testRunId
    )

    Write-Host "[Info] - Fetching test result files...Test Run ID:"$testRunId

    $deviceRunsUrl = $(UrlFromTemplate "${TD_TEST_DEVICE_SESSION_URL_TEMPLATE}" ${projectId} ${testRunId})
    $response = $(AuthCurl ${deviceRunsUrl})

    $deviceSessionIds = $($response | jq '.data[].id')
    Write-Host -ForegroundColor Green "[Info] - Fetched device session IDs:"$deviceSessionIds

    $testResultsDir = GetFullPath("${TEST_RESULTS_FOLDER}")
    Remove-Item -Path $testResultsDir/* -Recurse

    foreach ($deviceSessionId in $deviceSessionIds){
        Write-Host -ForegroundColor Green "[Info] - Check whether device was execlued, device session ID:"$deviceSessionId
        if ($(WasDeviceExcluded $projectId $testRunId $deviceSessionId) -eq 0){
            $deviceName = $(GetDeviceName $projectId $testRunId $deviceSessionId)
            GetDeviceResultFiles $projectId $testRunId $deviceSessionId "$deviceName"
            GetDeviceScreenshots $projectId $testRunId $deviceSessionId "$deviceName"
        }
    }
}
#************************************Private Function*************************************


#----------------------------------------Execution----------------------------------------
SystemSetup
#PullScriptsFromGit
#ZipTestScriptFiles
Initilization

$projectId = $(CreateProject $PROJECT_NAME)
$appFileId = UploadAppPackagesToCloud
$sctiptFileId = UploadTestScriptsToCloud
$testRunId = $(StartTestRun $projectId $appFileId $sctiptFileId)
GetTestRunResults $projectId $testRunId

cmd /c "pause"

