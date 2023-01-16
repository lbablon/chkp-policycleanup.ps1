# chkp-policycleanup.ps1 - Powershell script to cleanup a Checkpoint access layer based on hits count and disabled rules.

The script uses Checkpoint webservices api to connect to a management server and identify access rules with no hit and marked them as candidates for disabling or deletion. 

The script has been tested with R81.10 version of Checkpoint Management server.

![image](https://user-images.githubusercontent.com/121662789/212537727-c66f776f-ba5c-4623-8cd2-98339a7e2671.png)

## Usage

The script relies on the use of the custom field "field-3". Before running it, you have to make sure this field is enabled and dedicated to this usage on your SmartConsole for the targeted access layer :

![image](https://user-images.githubusercontent.com/121662789/212535466-78342951-9aed-47b5-8749-bbde442cb071.png)

If this custom field is already dedicated to another usage on your management server, you can use an other field by editing the following line in the code :

```
'disable-date'=$i.'custom-fields'.'field-3' #change this line to use another custom field
```

and 

```
"field-3"=get-date -Format "dd/MM/yyyy" #change this line to use another custom field
```

use the -WhatIf switch if you don't want to apply any changes to the database. The script will dipslay all changes that would have been made to the database without applying them.

-Quiet and -Password parameters can be used when calling the script if you want to run the script in an automatic way and in a regular basis. The script won't ask user for password nor confirmation for making changes, although it is not recommended to perfom changes in a production environment without a qualified operator to review the changes before applying it. Use at your own risk. 

All changes can be exported as a html report by using the -Output parameter. The specified file must be a .html file. If no absolute path is specified, the report will be saved under the current repository from where the script is run.

## Parameters

- **[-server]**, Checkpoint management server's ip address or fqdn.
- **[-user]**, user with sufficient permissions on the management server.
- **[-password]**, password for the api user.
- **[-accesslayer]**, access layer's name that corresponds to the policy package you want to export rules from.
- **[-disabledafter]**, followed by the number of months, disable all rules that have not matched for last x months.
- **[-deletedafter]**, followed by the number of months, delete all rules that have been disabled for more than x months.
- **[-outputfile]**, filepath where you want to export the results. This should be a .html file.
- **[-quiet]**, if specified no confirmation will be asked before making changes.
- **[-whatif]**, allows script to be run without applying any change.

## Examples

```
"./chkp-policycleanup.ps1" -Server 192.168.1.50 -user admin -AccessLayer "Standard" -DeleteAfter 2
```

Runs the script and deletes all rules that have been disable and where the date in custom field field-3 is older than 2 months without publishing changes to the database.

```
"./chkp-policycleanup.ps1" -Server 192.168.1.50 -user admin -AccessLayer "Standard" -DisableAfter 2 -publish
```

Runs the script and publishes changes to the database.

```
"./chkp-policycleanup.ps1" -Server 192.168.1.50 -user admin -password "Str0nK!" -AccessLayer "Standard" -DisableAfter 2 -quiet
```

Runs the script without any user interaction.

```
"./chkp-policycleanup.ps1" -Server 192.168.1.50 -user admin -AccessLayer "Standard" -DisableAfter 2 -whatif
```

Runs the script but only displays changes that would have been made to the database without applying them.

```
"./chkp-policycleanup.ps1" -Server 192.168.1.50 -user admin -AccessLayer "Standard" -DisableAfter 2 -output "results.html"
```

Runs the script and export the results into html file "results.html".

## Credits

Written by Lucas Bablon

This script was inspired by [CheckPointSW](https://github.com/CheckPointSW)'s own python script, however it is not a powershell translation of the original script. Both scripts differ in functionalities, parameters and code structure. You can find the python script right [here](https://github.com/CheckPointSW/PolicyCleanUp). 
