<#

.SYNOPSIS
This script is intended to clean up a Checkpoint access layer based on hits count.

.DESCRIPTION
The script uses Checkpoint webservices api to connect to a management server and list all access rules with 0 hit from a specified access layer. Listed access rules can then be 
disabled. Disabled rules will be updated with the current date as disabled date using cutom field "field-3", which need to be reserved for this usage beforhand on your SmartConsole.
You can specified the number of months from when the script will start counting the hits for each rules. The script also have an optional switch called -DeleteAfter that will delete 
all rules where field-3's date is older than the parameter specified when calling the script. You can also use the -whatif switch if you don't want to apply any changes to the database. 
By not using the -publish switch you will also be able to take over the session that made the changes on the SmartConsole in order to review the changes and make modifications before
publishing. The script has been tested with R81.10 version of Checkpoint Management server.

.EXAMPLE
"./chkp-policycleanup.ps1" -Server 192.168.1.50 -user admin -AccessLayer "Standard" -DisableAfter 2
Runs the script and disables all rules that have not match for the last 2 months from access layer named Standard without publishing changes to the database.

.EXAMPLE
"./chkp-policycleanup.ps1" -Server 192.168.1.50 -user admin -AccessLayer "Standard" -DeleteAfter 2
Runs the script and deletes all rules that have been disable and where the date in custom field field-3 is older than 2 months without publishing changes to the database.

.EXAMPLE
"./chkp-policycleanup.ps1" -Server 192.168.1.50 -user admin -AccessLayer "Standard" -DisableAfter 2 -publish
Runs the script and publishes changes to the database.

.EXAMPLE
"./chkp-policycleanup.ps1" -Server 192.168.1.50 -user admin -password "Str0nK!" -AccessLayer "Standard" -DisableAfter 2 -quiet
Runs the script without any user interaction.

.EXAMPLE
"./chkp-policycleanup.ps1" -Server 192.168.1.50 -user admin -AccessLayer "Standard" -DisableAfter 2 -whatif
Runs the script but only displays changes that would have been made to the database without applying them.

.EXAMPLE
"./chkp-policycleanup.ps1" -Server 192.168.1.50 -user admin -AccessLayer "Standard" -DisableAfter 2 -output "results.html"
Runs the script and export the results into html file "results.html".

.INPUTS
Server : IP address of the Checkpoint management server
User : User with sufficient permissions on the checkpoint management server
Password : Password for the api user 
AcessLayer : Access layer's name you want to list 0 hit rules from
DisableAfter : Disable all rules that have not matched for last x months
DeleteAfter : Delete all rules that are disabled and where custom field field-3 are older than x months
Publish : If specified all changes will be published to the database
OutputFile : html file where to save the results
Quiet : If specified no confirmation will be asked before making changes
Whatif : Allows script to be run without applying any change

.NOTES
Written by : Lucas Bablon
Version : 1.0
Link : https://github.com/lbablon

#>

#params
param 
(
    [Parameter(Mandatory=$true, HelpMessage="Checkpoint Management api's ip")]
    [string]$server,

    [Parameter(Mandatory=$true, HelpMessage="User with api management permission")]
    [string]$user,

    [Parameter(Mandatory=$false, HelpMessage="Password")]
    [string]$password,

    [Parameter(Mandatory=$true, HelpMessage="Access layer's name")]
    [string]$accesslayer,

    [Parameter(Mandatory=$false, HelpMessage="Export path for html file")]
    [string]$outputfile,

    [Parameter(Mandatory=$false, HelpMessage="Disable rules that have not matched for x month(s)")]
    [validateRange(1,999)]
    [string]$disableafter,

    [Parameter(Mandatory=$false, HelpMessage="Delete rules that were disabled for x month(s)")]
    [validateRange(0,999)]
    [string]$deleteafter,

    [Parameter(Mandatory=$false, HelpMessage="whatif mode that won't apply any change")]
    [switch]$whatif,

    [Parameter(Mandatory=$false, HelpMessage="if specified publish the results")]
    [switch]$publish,

    [Parameter(Mandatory=$false, HelpMessage="Non interactive mode")]
    [switch]$quiet
)

#if both disableafter and deleteafter are set by the user when calling the script then deleteafter must be strictly superior
if(($disableafter -and $deleteafter) -and ($deleteafter -le $disableafter))
{
    Write-Error "DeleteAfter parameter must be strictly superior than DisableAfter parameter."
    exit
}

#at least one switch msut be specified between disableafter and deleteafter
if(! $disableafter -and ! $deleteafter)
{
    Write-Error "At least one parameter between DisableAfter and DeleteAfter must be specified for the script to run."
    exit
}

#publish and whatif switches cannot be used at the same time
if($whatif -and $publish)
{
    Write-Error "Publish and WhatIf switches cannot be used at the same time."
    exit
}

if($whatif)
{
    Write-Host "`n"
    Write-Host -ForegroundColor Cyan -BackgroundColor Black "INFO : Script is running in whatif mode. No change will be performed to the database."
}

#tls support
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

##
##VARIABLES
##

#reset variables from previous run
$response=""
$sid=""
$rules=""
$allrules=""

#dates for disabling and deleting
$disabledate=Get-date((Get-Date).AddMonths(-$disableafter))
$deletedate=Get-date((Get-Date).AddMonths(-$deleteafter))
$date = Get-date -Format "o"

#confirmation object
$title="Confirm"
$question="Do you want to continue?"
$choices="&Yes","&No"

#html and css styling for outputfile
$html="<style>"
$html=$html+"BODY{background-color:white;font-family: Arial;}"
$html=$html+"TABLE{border: 1px;border-collapse: collapse;}"
$html=$html+"TH{border: 1px solid #ddd;padding: 15px;background-color: #300e7b;font-family: Arial;color: white;text-align: left;}"
$html=$html+"TD{border: 1px solid #ddd;padding: 15px;background-color: white;font-family: Arial;}"
$html=$html+"</style>"

$htmlintro=@"
    <br>
    <i>This report has been generated on $date for access layer "$accesslayer" on Checkpoint management server $server.</i>
    <br>
    <br>
"@

##
## FUNCTIONS
##

function chkp-login 
{
    param 
    (
        [Parameter(Mandatory=$true, HelpMessage="Checkpoint Management api's ip")]
        [string]$server,
        [Parameter(Mandatory=$true, HelpMessage="User with api management permission")]
        [string]$username,
        [Parameter(Mandatory=$false, HelpMessage="Password")]
        [string]$password
    )

    #password prompt
    if (! $password) 
    {
        $creds=get-credential -message "Please enter password" -username $username
        $password=$creds.GetNetworkCredential().password
    }

    $sessiondate=get-date -Format "dd/MM/yyyy"

    #body
    $body=@{

        "user"="$username"
        "password"="$password"
        "enter-last-published-session"="false"
        "session-name"="$user@$sessiondate"
        "session-description"="chkp-policycleanup.ps1"

    }
    
    $body=$body| convertto-json -compress
    
    #create login URI
    $loginURI="https://${server}/web_api/login"

    #allow self-signed certificates
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback={$true}

    #api call
    $response=Invoke-WebRequest -Uri $loginURI -Body $body -ContentType application/json -Method POST

    #make the content of the response a powershell object
    $responsecontent=$response.Content | ConvertFrom-Json

    #return sid
    $sid=$responsecontent.sid
    return $sid
}

function chkp-logout 
{
    param 
    (
        [Parameter(Mandatory=$true, HelpMessage="Checkpoint Management api's ip")]
        [string]$server,
        [Parameter(Mandatory=$true, HelpMessage="api session id")]
        [string]$sid
    )
     
    #headers
    $headers=@{"x-chkp-sid"=$sid}
    $global:headers=$headers | ConvertTo-Json -Compress
 
    #body
    $body=@{}
    $body=$body| convertto-json -compress

    #create logout URI
    $logoutURI="https://${server}/web_api/logout"

    $response=Invoke-WebRequest -Uri $logoutURI -Body $body -Headers $headers -ContentType application/json -Method POST
}

function chkp-accessrules
{
    param
    (
        [Parameter(Mandatory=$true, HelpMessage="Checkpoint Management api's ip")]
        [string]$server,
        
        [Parameter(Mandatory=$true, HelpMessage="api current session id")]
        [string]$sid,

        [Parameter(Mandatory=$true, HelpMessage="Access layer you want to list rules from")]
        [string]$accesslayer,
        
        [Parameter(Mandatory=$false, HelpMessage="Date from which hits are calculated")]
        [datetime]$fromdate="01-01-1993"
    )

    #initiliaze array that will contains all rules
    $allrules=@()

    #offset corresponds to the rule number from where the api will start to query
    $offset=0

    #headers
    $headers=@{"x-chkp-sid"=$sid}

    $global:headers=$headers | ConvertTo-Json -Compress

    #api request to get the total number of rules so that we can use the progress bar
    $body=@{

        "details-level"="standard"
        "name"=$AccessLayer
        "use-object-dictionary"="false"
        "show-hits"="true"
        "offset"=0
        "limit"=1

    }

    $body=$body | ConvertTo-Json -Compress

    #request
    $requestURI="https://${server}/web_api/show-access-rulebase"
    $response=Invoke-WebRequest -Uri $requestURI -Body $body -ContentType application/json -Method POST -Headers $headers

    #make the content of the response a powershell object and get total number of rules
    $rulesnumber=$response | ConvertFrom-Json
    $rulesnumber=$rulesnumber.total

    #query all rules from offset to total number of rules with a limit of 50 because more than that in a single request seems to be stressful for the management server
    Write-Host "Fetching access rules from access layer $accesslayer..."

    #save fecthing execution time to display later
    $exectime=[System.Diagnostics.Stopwatch]::StartNew()

    do 
    {
        #progress bar
        $completed=[math]::round(($offset/$rulesnumber)*100)
        Write-Progress -Activity "Listing all rules" -Status "$completed% complete" -PercentComplete $completed
        Start-Sleep -Milliseconds 300

        #body
        #in a general way the api is limited to 500 objects for each request. 100 and above are too slow, 50 is more precise to display task advancement 
        #do not set the details-level to full unless you really need it because it will slow down the query and cause errors 500
        $body=@{

            "details-level"="standard"
            "name"=$AccessLayer
            "use-object-dictionary"="false"
            "show-hits"="true"
            "hits-settings"=@{
                "from-date"=get-date($fromdate) -Format "yyyy-MM-dd"
            }
            "offset"=$offset
            "limit"=100

        }

        $body=$body | ConvertTo-Json -Compress

        #request
        $requestURI="https://${server}/web_api/show-access-rulebase"
        $response=Invoke-WebRequest -Uri $requestURI -Body $body -ContentType application/json -Method POST -Headers $headers
   
        #make the content of the response a powershell object
        $rules=$response | ConvertFrom-Json

        #merge previous result from the do loop with current request
        $allrules+=$rules.rulebase.rulebase

        #set offset to the last rule listed by the query
        $offset=$rules.to

    #if the last rule from current query is not equal to the total rules number we loop again
    } while ($offset -ne $rulesnumber)

    $exectime.stop()

    $duration=[math]::round($exectime.elapsed.totalseconds,2)

    #display fetch exec time
    Write-Host "Done. $rulesnumber rules were fetched in $duration seconds.`n"

    #here you can customize the output with the information you need
    $allrules=$allrules | % {

        $i=$_
        
        New-Object -TypeName psobject -Property @{

            'rule-number'=$i.'rule-number'
            'name'=$i.name
            'source'=$i.source.name -join ";"
            'source-negate'=$i.'source-negate'
            'destination'=$i.destination.name -join ";"
            'destination-negate'=$i.'destination-negate'
            'services'=$i.service.name -join ";"
            'action'=$i.action.name
            'track'=$i.track.type.name
            'comments'=$i.comments
            'install-on'=$i.'install-on'.name
            'enabled'=$i.enabled
            'disable-date'=$i.'custom-fields'.'field-3'
            'hits'=$i.hits.value
            'creation-time'=$i.'meta-info'.'creation-time'.'iso-8601'
            'owner'=$i.'meta-info'.creator
            'last-modify-time'=$i.'meta-info'.'last-modify-time'.'iso-8601'
            'last-modifier'=$i.'meta-info'.'last-modifier'
            'uid'=$i.uid

        }
    }

    #function output is a powershell object containing all rules from the access layer
    return $allrules
}

function chkp-disablerules
{
param
    (
        [Parameter(Mandatory=$true, HelpMessage="Checkpoint Management api's ip")]
        [string]$server,
        
        [Parameter(Mandatory=$true, HelpMessage="api current session id")]
        [string]$sid,

        [Parameter(Mandatory=$true, HelpMessage="Access layer's name")]
        [string]$accesslayer,

        [Parameter(Mandatory=$true, HelpMessage="Rules'id your want to disable")]
        [string[]]$rules
    )

    #headers
    $headers=@{"x-chkp-sid"=$sid}

    $global:headers=$headers | ConvertTo-Json -Compress

    #used for the progress bar
    $offset=0
    $rulesnumber=$rules.count

    #disable each rules 
    Write-Host "`n"
    Write-Host "Disabling $rulesnumber rules..."

    $rules | %{

        $rule=$_

        #progress bar
        $completed=[math]::round(($offset/$rulesnumber)*100)
        Write-Progress -Activity "Candidate rules are being disabled." -Status "$completed% complete" -PercentComplete $completed
        Start-Sleep -Milliseconds 300

        #body
        $body=@{

            "uid"=$rule
            "enabled"="false"
            "layer"=$accesslayer
            "custom-fields"=@{
                "field-3"=get-date -Format "dd/MM/yyyy"
            }
        }

        $body=$body | ConvertTo-Json -Compress
        
        #request
        $requestURI="https://${server}/web_api/set-access-rule"
        $response=Invoke-WebRequest -Uri $requestURI -Body $body -ContentType application/json -Method POST -Headers $headers

        $offset++
    }
}

function chkp-deleterules
{
    param
    (
        [Parameter(Mandatory=$true, HelpMessage="Checkpoint Management api's ip")]
        [string]$server,
        
        [Parameter(Mandatory=$true, HelpMessage="api current session id")]
        [string]$sid,

        [Parameter(Mandatory=$true, HelpMessage="Access layer's name")]
        [string]$accesslayer,

        [Parameter(Mandatory=$true, HelpMessage="Rules'id your want to delete")]
        [string]$rules  
    )

    #headers
    $headers=@{"x-chkp-sid"=$sid}

    $global:headers=$headers | ConvertTo-Json -Compress

    #used for the progress bar
    $offset=0
    $rulesnumber=$rules.count

    #delete each rules
    Write-Host "`n"
    Write-Host "Deleting $rulesnumber rules..."

    $rules | %{

        $rule=$_

        #progress bar
        $completed=[math]::round(($offset/$rulesnumber)*100)
        Write-Progress -Activity "Candidate rules are being deleted." -Status "$completed% complete" -PercentComplete $completed
        Start-Sleep -Milliseconds 300

        #body
        $body=@{

            "uid"=$rule
            "layer"=$accesslayer
        }
        
        $body=$body | ConvertTo-Json -Compress

        #request
        $requestURI="https://${server}/web_api/delete-access-rule"
        $response=Invoke-WebRequest -Uri $requestURI -Body $body -ContentType application/json -Method POST -Headers $headers

    }

        $offset++
}

function chkp-publish
{
    param
    (
        [Parameter(Mandatory=$true, HelpMessage="Checkpoint Management api's ip")]
        [string]$server,
        
        [Parameter(Mandatory=$true, HelpMessage="api current session id")]
        [string]$sid,

        [Parameter(Mandatory=$false, HelpMessage="Description text to attach to the session")]
        [string]$description="chkp-cleanuppolicy.ps1"
    )

    Write-Host "Session with id $sid is being published to $server."
    
    #headers
    $headers=@{"x-chkp-sid"=$sid}

    $global:headers=$headers | ConvertTo-Json -Compress
 
    #body
    $body=@{}
        
    $body=$body | ConvertTo-Json -Compress

    $requestURI="https://${server}/web_api/publish"
    $response=Invoke-WebRequest -Uri $requestURI -Body $body -ContentType application/json -Method POST -Headers $headers

    $taskid=$response | ConvertFrom-Json

    #check publish task current progression
    $body=@{
        
        "task-id"=$taskid.'task-id'

    }
        
    $body=$body | ConvertTo-Json -Compress

    #task percentae progression
    $completed=0

    #while tasks has not finished show progress and wait more
    while($completed -ne "100")
    {    
        $requestURI="https://${server}/web_api/show-task"
        $response=Invoke-WebRequest -Uri $requestURI -Body $body -ContentType application/json -Method POST -Headers $headers
        $task=$response | ConvertFrom-Json

        #progress bar
        $taskprogress=$task.tasks.status
        $completed=$task.tasks.'progress-percentage'
        Write-Progress -Activity "Publishing changes $taskprogress" -Status "$completed% complete" -PercentComplete $completed
        start-sleep -Milliseconds 250
    }

}

function chkp-discardsession 
{
    param 
    (
        [Parameter(Mandatory=$true, HelpMessage="Checkpoint Management api's ip")]
        [string]$server,
        [Parameter(Mandatory=$true, HelpMessage="api session id")]
        [string]$sid
    )

    #body
    $body=@{}
    $body=$body| convertto-json -compress
    
    #headers
    $headers=@{"x-chkp-sid"=$sid}
    $global:headers=$headers | ConvertTo-Json -Compress

    #create logout URI
    $requestURI="https://${server}/web_api/discard"

    #api call
    $response=Invoke-WebRequest -Uri $requestURI -Body $body -Headers $headers -ContentType application/json -Method POST
}

##
##SCRIPT
##

#login
Write-Host "`n"
Write-Host "Connecting to api..."

try
{
    $sid=chkp-login -server $server -username $user -password $password
}
catch
{
    #exit because could not establish a session with api
    Write-Warning $_.exception.message
    Write-Error "Could not establish session with management server $server."
    exit
}

Write-Host -ForegroundColor green -backgroundcolor black "SUCCESS`n"

#list all rules
try
{
    $allrules=chkp-accessrules -server $server -sid $sid -accesslayer $accesslayer -fromdate $disabledate
}
catch
{
    #logout and exit if the script could not have fetched rules
    Write-Warning $_.exception.message
    Write-Error "Could not fetch rules from $server. Exiting.`n"

    #terminates api current session
    Write-Host "Closing connection with management server..."
    try
    {
        chkp-logout -server $server -sid $sid
    }
    catch
    {
        Write-Warning $_.exception.message
        Write-Error "Could not terminate session $sid.`n"
        [switch]$logouterror=$true
    }

    if(!$logouterror)
    {
        Write-Host -ForegroundColor green -backgroundcolor black "SUCCESS`n"
    }

    exit  
}

##
##DISABLE
##

#disable rules
if ($disableafter)
{
    #disable rules with 0 hit
    $rulestodisable=$allrules | ? {$_.enabled -like "True" -and $_.hits -eq 0}
    $rulescount=$rulestodisable.count

    Write-Host "The following $rulescount rules will be disabled :`n" 
    $rulestodisable | select 'rule-number','name','uid' | ft

    #if quiet switch then proceed else ask for confirmation
    if ($quiet)
    {
        #do not perform delete action if whatif mode is enabled
        if (! $whatif)
        {
            try
            {
                chkp-disablerules -server $server -sid $sid -rules $rulestodisable.uid -accesslayer $accesslayer
            }
            catch
            {
                #display error message 
                Write-Warning $_.exception.message
                Write-Error "Could not disable rules.`n"

                #if error occured set this variable in order not to publish
                [switch]$generalerror=$true
                [switch]$disableerror=$true
            }
        }
        
        if(!$disableerror)
        {
            Write-Host -ForegroundColor green -backgroundcolor black "SUCCESS`n" 
        }

        $confirmdisable=0
    }
    else
    {
        #ask for confirmation
        $confirmdisable = $Host.UI.PromptForChoice($title, $question, $choices, 1)
        if ($confirmdisable -eq 0)
        {
            #do not perform delete action if whatif mode is enabled
            if (! $whatif)
            {
                try
                {
                    chkp-disablerules -server $server -sid $sid -rules $rulestodisable.uid -accesslayer $accesslayer
                }
                catch
                {
                    #display error message
                    Write-Warning $_.exception.message
                    Write-Error "Could not disable rules.`n"

                    #if error occured set this variable in order not to publish
                    [switch]$generalerror=$true
                    [switch]$disableerror=$true

                }
            }
            
            if(!$disableerror)
            {
                Write-Host -ForegroundColor green -backgroundcolor black "SUCCESS`n" 
            }

        }
        else
        {
            Write-Host "`n"
            Write-Host "Operation canceled.`n"
        }       
    }
    
    #if outputfile is specified and disable action has not been canceled then export results
    if ($outputfile -and $confirmdisable -eq 0 -and ! $generalerror)
    {

    $disabledhtmltitle=@"
    <font size="+3"><b>Rules disabled by the script</b></font>
    <br>
    <br>
"@

        $disabledhtmlbody=$rulestodisable | 
            select 'rule-number','name','source','source-negate','destination','destination-negate','services','action','track','comments','install-on','enabled','disable-date','hits','creation-time','owner','last-modify-time','last-modifier','uid' |
            sort 'rule-number' |
            ConvertTo-Html -Head $html
    }   
}

##
##DELETION
##

#delete all rules that are disabled for more than deleteafter paramater
if ($deleteafter)
{   
    #rules have to be fetched again because we do not want to be restricted by disableafter switch
    if ($disableafter)
    { 
        Write-Host "Fetching all candidate rules for deletion without considering -DisabledAfter switch...`n"
        
        try
        {
            $allrulesalltime=chkp-accessrules -server $server -sid $sid -accesslayer $accesslayer
        }
        catch
        {
            #exit because could not establish a session with api
            Write-Warning $_.exception.message
            Write-Error "Could not fetch rules from access layer $accesslayer.`n"

            #if error occured set this variable in order not to publish
            [switch]$generalerror=$true
        }
    }
    else
    {
         $allrulesalltime=$allrules   
    }

    $rulestodelete = $allrulesalltime | ? {$_.enabled -like "False" -and $_.'disable-date' -ne "" -and (get-date($_.'disable-date')) -lt $deletedate}
    $rulescount=$rulestodelete.count

    Write-Host "The following $rulescount rules will be deleted :`n" 
    $rulestodelete | select 'rule-number','name','uid' | ft

    #if quiet switch then process else ask for confirmation
    if ($quiet)
    {
        #do not perform delete action if whatif mode is enabled
        if (! $whatif)
        {
            try
            {
                chkp-deleterules -server $server -sid $sid -accesslayer $accesslayer -rules $rulestodelete.uid
            }
            catch
            {
                #display error message
                Write-Warning $_.exception.message
                Write-Error "Could not delete rules.`n"

                #if error occured set this variable in order not to publish
                [switch]$generalerror=$true
                [switch]$deleteerror=$true
            }
        }
        
        if(!$deleteerror)
        {
            Write-Host -ForegroundColor green -backgroundcolor black "SUCCESS`n"
        }

        $confirmdelete=0
    }
    else
    {
        #ask for confirmation
        $confirmdelete = $Host.UI.PromptForChoice($title, $question, $choices, 1)
        if ($confirmdelete -eq 0)
        {
            #do not perform delete action if whatif mode is enabled
            if (! $whatif)
            {
                try
                {
                    chkp-deleterules -server $server -sid $sid -accesslayer $accesslayer -rules $rulestodelete.uid
                }
                catch
                {
                    #display error message
                   
                    Write-Warning $_.exception.message
                    Write-Error "Could not delete rules`n"

                    #if error occured set this variable in order not to publish
                    [switch]$generalerror=$true
                    [switch]$deleteerror=$true
                }
            }

            if(!$deleteerror)
            {
                Write-host -ForegroundColor green -backgroundcolor black "SUCCESS`n" 
            }
            else
            {
                Write-Host "`n"
                Write-Host "Operation canceled.`n"
            }  
        }
    }
        
    #if outputfile is specified and deletion has not been canceled then export results
    if ($outputfile -and $confirmdelete -eq 0 -and ! $generalerror)
    {

    $deletedhtmltitle=@"
    <br>
    <font size="+3"><b>Rules deleted by the script</b></font>
    <br>
    <br>
"@

    $deletedhtmlbody=$rulestodelete | 
    select 'rule-number','name','source','source-negate','destination','destination-negate','services','action','track','comments','install-on','enabled','disable-date','hits','creation-time','owner','last-modify-time','last-modifier','uid' |
    sort 'rule-number' |
    ConvertTo-Html -Head $html

    }
}

#if error discard all changes
if($generalerror)
{
    try
    {
        Write-Host "Reverting all changes due to error..."
        chkp-discardsession -server $server -sid $sid
    }
    catch
    {
        Write-Warning $_.exception.message
        Write-Error "Could not discard changes. Please connect to the management server to perform discard manually.`n"
        [switch]$discarderror=$true
    }

    if(!$discarderror)
    {
        Write-Host -ForegroundColor green -backgroundcolor black "SUCCESS`n"
    }
}

##
##PUBLISH
##

#if the script runs without the whatif switch and at least one action has been take and no error detected then publish
if( $publish -and ! $whatif -and ! ($confirmdisable -eq 1 -and $confirmdelete -eq 1) -and ! $generalerror)
{
    try
    {
        chkp-publish -server $server -sid $sid
    }
    catch
    {
        #display error message
        Write-Warning $_.exception.message
        Write-Error "Could not publish session. Session can be taken over in SmartConsole in order to review changes.`n"

        #if error occured set this variable in order not to publish
        [switch]$publisherror=$true
    }
    if (!$publisherror)
    {
        Write-Host -ForegroundColor Green -BackgroundColor black "SUCCESS`n"
    }
}
elseif(!$publish -and ! $whatif -and ! ($confirmdisable -eq 1 -and $confirmdelete -eq 1) -and ! $generalerror)
{
   Write-Host -ForegroundColor Cyan -BackgroundColor Black "INFO : -Publish switch was not specified. Session can be taken over in SmartConsole in order to review changes.`n"
}

##
##LOGOUT
##

#terminates api current session
Write-Host "Closing connection with management server..."
try
{
    chkp-logout -server $server -sid $sid
}
catch
{
    Write-Warning $_.exception.message
    Write-Error "Could not terminate session $sid.`n"
    [switch]$logouterror=$true
}

if(!$logouterror)
{
    Write-Host -ForegroundColor green -backgroundcolor black "SUCCESS`n"
}

##
##REPORT
##

#report creation
if ($outputfile -and ($disabledhtmltitle -or $deletedhtmltitle))
{
    #script execution information
    $htmlintro | Out-File $outputfile -Append

    $disabledhtmltitle+$disabledhtmlbody+$deletedhtmltitle+$deletedhtmlbody | Out-File $outputfile -Append

    $filepath=(Get-ChildItem $outputfile).versioninfo.filename
    Write-Host -ForegroundColor Cyan -BackgroundColor Black "INFO : Report has been saved in $filepath.`n"
}
