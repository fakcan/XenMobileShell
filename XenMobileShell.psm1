#
# Forked and modified by Fırat AKCAN
# 14.08.2018 - akcan.firat |at| gmail |dot| com
# 
#
# Version: 1.2.0
# Revision 2016.10.19: improved the new-xmenrollment function: added parameters of notification templates as well as all other options. Also included error checking to provide a more useful error message in case incorrect information is provided to the function. 
# Revision 2016.10.21: adjusted the confirmation on new-xmenrollment to ensure "YesToAll" actually works when pipelining. Corrected typo in notifyNow parameter name.
# Revision 1.1.4 2016.11.24: corrected example in new-xmenrollment
# Revision 1.2.0 2016.11.25: added the use of a PScredential object with the new-xmsession command.   



#the request object is used by many of the functions. Do not delete.  
$request = [pscustomobject]@{
    method = $null
    url = $null
    header = $null
    body = $null
}

function convertFrom-MisinterpretedUtf8([string] $String) {
	return [System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::GetEncoding(28591).GetBytes($String))
}

function get-authToken {
	<#
	.SYNOPSIS
	This function will authenticate against the server and will provide you with an authentication token.
	Most cmdlets in this module require a token in order to authenticate against the server. 

	.DESCRIPTION
	This cmdlet will authenticate against the server and provide you with a token. It requires a username, password and server address. 
	The cmdlet assumes you are connecting to port 4443. All parameters can be piped into this command.  

	.PARAMETER user
	Specify the username. This username must have API access. 

	.PARAMETER password
	Specify the password to use. 

	.PARAMETER server
	Specify the servername. IP addresses cannot be used. Do no specify a port number. Example: mdm.citrix.com

	.PARAMETER port
	Specify the port to connect to. This defaults to 4443. Only specify this parameter is you are using a non-standard port. 

	.EXAMPLE
	$token = get-authToken -user "admin" -password "citrix123" -server "mdm.citrix.com
	#> 
	
	param(
		[parameter(ValueFromPipelineByPropertyName,ValueFromPipeLine)][string]$user,
		[parameter(ValueFromPipelineByPropertyName,ValueFromPipeLine)][string]$password,
		[parameter(ValueFromPipelineByPropertyName,ValueFromPipeLine)][string]$server,
		[parameter(ValueFromPipeLIneByPropertyName)][string]$port = "4443"
	)

	$URL = "https://" + $server + ":" + $port + "/xenmobile/api/v1/authentication/login"
	$header = @{ 'Content-Type' = 'application/json'}
	$body = @{ login = $user; password = $password }
	$jsonBody = ConvertTo-Json $body
	Write-Verbose ("Submitting authentication request `nbody:" + $jsonBody)
	# FIX CERT PROBLEM
	[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
	$returnedToken = Invoke-RestMethod -Uri $URL -Method Post -Body $jsonBody -Headers $header
	# FIX CERT PROBLEM
	[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$false}
	Write-Verbose ("received token: " + $returnedToken) 
	return [string]$returnedToken.auth_token
}

function getObject {
	param(
		[parameter(mandatory)]$url
	)

	Process {
		$request.method = "GET"
		$request.url = "https://" + $XMSServer + ":" + $XMSServerPort + "/xenmobile/api/v1" + $url
		$request.header = @{ 'auth_token' = $XMSAuthToken ; 'Content-Type' = 'application/json' }
		$request.body = $null
		Write-Verbose (ConvertTo-Json $request)
	}
	end {
		return submitToServer $request
	}
}

function putObject {
	param(
		[parameter(mandatory)]$url,
		[parameter(mandatory)]$target
	)

	Process {
		Write-Verbose "Submitting PUT request"
		$request.method = "PUT"
		$request.url = "https://" + $XMSServer + ":" + $XMSServerPort + "/xenmobile/api/v1" + $url
		$request.header = @{ 'auth_token' = $XMSAuthToken ; 'Content-Type' = 'application/json' }
		$request.body = $target
	}
	end {
		return submitToServer $request
	}
}

function submitToServer($request) {
	try {		
		$result = Invoke-RestMethod -Uri $request.url -Method $request.method -Body (ConvertTo-Json -Depth 8 $request.body) -Headers $request.header -ErrorAction Stop
		Write-Verbose ($result | ConvertTo-Json)
		return $result
	}
	catch {
		Write-Host "Submission of the request to the server failed." -ForegroundColor Red
		$ErrorMessage = $_.Exception.Message
		Write-Host $ErrorMessage -ForegroundColor Red
	}    
}

function search {
	param(
		[parameter()][int]$startIndex = 0,
		[parameter()]$criteria = $null,
		[parameter(mandatory)]$url,
		[parameter()]$filterIds = "[]",
		[parameter()][int]$ResultSetSize = 999         
	)
	Process { 
		$request.method = "POST"
		$request.url = "https://" + $XMSServer + ":" + $XMSServerPort + "/xenmobile/api/v1" + $url
		$request.header = @{ 'auth_token' = $XMSAuthtoken ;
							 'Content-Type' = 'application/json' }

		$request.body = @{
			start = [int]$startIndex;
			limit = [int]$ResultSetSize;
			sortOrder =  "ASC";
			sortColumn = "ID";
			search = $criteria;
			enableCount = "true";
			filterIds = $filterIds
		}
		Write-Verbose ($request | ConvertTo-Json)
	}
	end {
		return submitToServer $request
	}
}

function checkSession {
	if ($XMSessionExpiry -gt (get-date)) {
		Write-Verbose "Session is still active."
		if ($XMSessionUseInactivity -eq $true) {
			$timeToExpiry = (($XMSessionInactivityTimer) * 60) - 30
			Set-Variable -name "XMSessionExpiry" -Value (get-Date).AddSeconds($timeToExpiry) -scope global
			Write-Verbose ("Session expiry extended by " + $timeToExpiry + " sec. New expiry time is: " + $XMSessionExpiry)
		}
		return $true
	} 
	else {
		Write-Host "Session has expired. Please create a new XMSession using the New-XMSession command." -ForegroundColor Yellow
		return $false
		#break
	}
}

function deleteObject {
	param(
		[parameter(mandatory)]$url,
		[parameter()][string[]]$target
	)
	Process { 
		$request.method = "DELETE"
		$request.url = "https://" + $XMSServer + ":" + $XMSServerPort + "/xenmobile/api/v1" + $url
		$request.header = @{ 'auth_token' = $XMSAuthToken ;
							 'Content-Type' = 'application/json' }
		$request.body = $target
		Write-Verbose ($request | ConvertTo-Json)
	}
	End {
		return submitToServer $request
	}  
}

function postObject {
	param(
		[parameter(mandatory)]$url,
		[parameter(mandatory)]$target
	)

	Process { 
		Write-Verbose "submitting POST request"
		$request.method = "POST"
		$request.url = "https://" + $XMSServer + ":" + $XMSServerPort + "/xenmobile/api/v1" + $url
		$request.header = @{ 'auth_token' = $XMSAuthToken ;
							 'Content-Type' = 'application/json' }
		$request.body = $target
		Write-Verbose ($request | ConvertTo-Json)
	}
	End {
		return submitToServer $request
	}
}

function New-XMSession {
	<#
	.SYNOPSIS
	Starts a XMS session. Run this before running any other commands. 

	.DESCRIPTION
	This command will login to the server and get an authentication token. This command will set several session variables that are used by all the other commands.
	This command must be run before any of the other commands. 
	This command can use either a username or password pair entered as variables, or you can use a PScredential object. To create a PScredential object,
	run the get-credential command and store the output in a variable. 
	If both a user, password and credential are provided, the credential will take precedence. 

	.PARAMETER -user
	Specify the user with required permissions to access the XenMobile API. 

	.PARAMETER -password
	Specify the password for the API user. 

	.PARAMETER -credential
	Specify a PScredential object. This replaces the user and password parameters and can be used when stronger security is desired. 

	.PARAMETER -server
	Specify the server you will connect to. This should be a FQDN, not IP address. PowerShell is picky with regards to connectivity to encrypted paths. 
	Therefore, the servername must match the certificate, be valid and trusted by system you are running these commands. 

	.PARAMETER -port
	You can specify an alternative port to connect to the server. This is optional and will default to 4443 if not specified.

	.EXAMPLE
	New-XMSession -user "admin" -password "password" -server "mdm.citrix.com"

	.EXAMPLE
	New-XMSession -user "admin" -password "password" -server "mdm.citrix.com" -port "4443"

	.EXAMPLE
	$credential = get-credential
	new-xmsession -credential $credential -server mdm.citrix.com

	.EXAMPLE
	new-xmsession -credential (get-credential) -server mdm.citrix.com

	#>
	
	[CmdletBinding()]
	param(
		[parameter(ValueFromPipelineByPropertyName,ValueFromPipeLine)][string]$user,
		[parameter(ValueFromPipelineByPropertyName,ValueFromPipeLine)][string]$password,
		[parameter(valueFromPipelineByPropertyName,ValueFromPipeLine)]$credential=$null,
		[parameter(ValueFromPipelineByPropertyName,ValueFromPipeLine)][string]$server,
		[parameter(ValueFromPipeLIneByPropertyName)][string]$port = "4443"
	)
	
	Process {
		Write-Verbose "Setting the server port. "
		if ($port -ne "4443") {
			Set-Variable -name "XMSServerPort" -Value $port -scope Global 
		} 
		else {
			Set-Variable -name "XMSServerPort" -Value "4443" -scope Global
		}

		Write-Verbose "creating an authentication token, and setting the XMSAuthToken and XMSServer variables"

		if ($credential -ne $null) {
			$user = $credential.username
			$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($credential.password)
			$password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
		}
		
		try {
			Set-Variable -name "XMSAuthToken" -Value (get-authToken -user $user -password $password -server $server -port $XMSServerPort) -Scope global -ErrorAction Stop
		}
		catch {
			Write-Host "Authentication failed." -ForegroundColor Yellow
			break
		}
		$password = $null
		Set-Variable -name "XMSServer" -Value $server -scope global
		Set-Variable -name "XMSessionStart" -Value (get-date) -scope global
		Write-Verbose ("Setting session start to: " + $XMSessionStart )
		Write-Verbose "Checking the type of timeout the server uses:"
		if ((Get-XMServerProperty -name "xms.publicapi.timeout.type" -skipCheck $true).value -eq "INACTIVITY_TIMEOUT") {
			Write-Verbose "   Server is using an inactivity timeout for the API session. This is preferred."
			Set-Variable -name "XMSessionUseInactivity" -value $true -scope global
			Set-Variable -name "XMSessionInactivityTimer" -Value ([convert]::ToInt32((Get-XMServerProperty -name "xms.publicapi.inactivity.timeout" -skipCheck $true).value)) -scope global
			$timeToExpiry = (($XMSessionInactivityTimer) * 60) - 30 
			Set-Variable -name "XMSessionExpiry" -Value (get-Date).AddSeconds($timeToExpiry) -scope global
			Write-Verbose ("The session expiry time is set to: " + $XMSessionExpiry)
		}
		else {
			Write-Verbose "   Server is using a static timeout. The use of an inactivity timeout is recommended."
			Set-Variable -name "XMSessionUseInactivity" -value $false -scope global
			$timeToExpiry = ([convert]::ToInt32((Get-XMServerProperty -name "xms.publicapi.static.timeout" -skipCheck $true).value))* 60 - 30
			Write-Verbose ("expiry in seconds: " + $timeToExpiry)
			Set-Variable -name "XMSessionExpiry" -Value (get-Date).AddSeconds($timeToExpiry) -scope global
			Write-Verbose ("The session expiry time is set to: " + $XMSessionExpiry)
        }
		Write-Host "A session has been started"
		Write-Verbose ("Authentication successful. Token: " + $XMSAuthToken + "`nSession will expire at: " + $XMSessionExpiry)
	}
}

function Get-XMDeviceProperty {
	<#
	.SYNOPSIS
	Gets the properties for the device. 

	.DESCRIPTION
	Gets the properties for the device. This is different from the get-xmdeviceinfo command which includes the properties but also returns all other information about a device. This command returns a subset of that data. 

	.PARAMETER id
	Specify the ID of the device for which you want to get the properties. 

	.EXAMPLE
	get-xmdeviceproperty -id "8" 

	.EXAMPLE
	get-xmdevice -name "Ward@citrix.com" | get-xmdeviceproperties
	#>
	[CmdletBinding()]
    param(
        [parameter(ValueFromPipelineByPropertyName,mandatory)][string]$id      
    )

    Begin {
        if((checkSession) -eq $false){
			break
		}
    }
    Process {
		$result = getObject -url ( "/device/properties/" + $id )
		return $result.devicePropertiesList.deviceProperties.devicePropertyParameters
    }
}

function Remove-XMClientProperty {
	<#
	.SYNOPSIS
	Removes a client property. 

	.DESCRIPTION
	Removes a client property. This command accepts pipeline input.  

	.PARAMETER key
	Specify the key of the propery to remove. This parameter is mandatory. 

	.EXAMPLE
	remove-xmclientproperty -key "TEST_PROPERTY"
	#>
	[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
    param(
        [parameter(ValueFromPipelineByPropertyName,mandatory)][string[]]$key            
    )
	Begin {
        if((checkSession) -eq $false){
			break
		}
    }
    Process {
        if ($PSCmdlet.ShouldProcess($key)) {    
            Write-Verbose ("Deleting: " + $key)
            deleteObject -url ("/clientproperties/" + $key) -target $null
        }
    }
}

function Set-XMClientProperty {
	<#
	.SYNOPSIS
	edit a client property. 

	.DESCRIPTION
	edit a client property. Specify the key. All other properties are optional and will unchanged unless otherwise specified. 

	.PARAMETER displayname
	Specify name of the property. 

	.PARAMETER description
	Specify the description of the property.

	.PARAMETER key
	Specify the key. 

	.PARAMETER value
	Specify the value of the property. 

	.EXAMPLE
	set-xmclientProperty -key "ENABLE_TOUCH_ID_AUTH" -value "false"

	#>
	[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]

	param(
		[parameter(ValueFromPipelineByPropertyName)][string]$displayname = $null,
		[parameter(ValueFromPipelineByPropertyName)][string]$description = $null,
		[parameter(ValueFromPipelineByPropertyName,mandatory)][string]$key,
		[parameter(ValueFromPipelineByPropertyName)][string]$value = $null
	)

	Begin {
		if((checkSession) -eq $false){
			break
		}
	}

	Process {
		if ($PSCmdlet.ShouldProcess($key)) {
			if (!$displayname) {
				$displayname = (Get-XMClientProperty -key $key).displayName
			}
			if (!$description) {
				$description = (Get-XMClientProperty -key $key).description
			}
			if (!$value) {
				$value = (Get-XMClientProperty -key $key).value
			}
			$body = @{
				displayName = $displayname;
				description = $description;
				value = $value
			}
			Write-Verbose ("changing: displayName: " + $displayname + ", description: " + $description + ", key: " + $key + ", value: " + $value )
			putObject -url ("/clientproperties/" + $key) -target $body
		}
	}
}

function New-XMClientProperty {
	<#
	.SYNOPSIS
	Creates a new client property. 

	.DESCRIPTION
	Creates a new client property. All parameters are required. Use this to create/add new properties. To change an existing property, use set-xmclientproperty

	.PARAMETER displayname
	Specify name of the property. 

	.PARAMETER description
	Specify the description of the property.

	.PARAMETER key
	Specify the key. 

	.PARAMETER value
	Specify the value of the property. The value set when the property is created is used as the default value. 

	.EXAMPLE
	new-xmclientProperty  -displayname "Enable touch ID" -description "Enables touch ID" -key "ENABLE_TOUCH_ID_AUTH" -value "true"

	#>
	[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
	param(
		[parameter(ValueFromPipelineByPropertyName,mandatory)][string]$displayname,
		[parameter(ValueFromPipelineByPropertyName,mandatory)][string]$description,
		[parameter(ValueFromPipelineByPropertyName,mandatory)][string]$key,
		[parameter(ValueFromPipelineByPropertyName,mandatory)][string]$value
	)
	Begin {
		if((checkSession) -eq $false){
			break
		}
	}
	Process {
		if ($PSCmdlet.ShouldProcess($key)) {        
			$body = @{
				displayName = $displayname;
				description = $description;
				key = $key;
				value = $value
			}
			Write-Verbose ("creating: displayName: " + $displayname + ", description: " + $description + ", key: " + $key + ", value: " + $value )
			postObject -url "/clientproperties" -target $body
		}
	}
}

function Get-XMClientProperty {
	<#
	.SYNOPSIS
	Queries the server for client properties. 

	.DESCRIPTION
	Queries the server for server properties. Without any parameters, this command will return all properties. 

	.PARAMETER key
	Specify the parameter for which you want to get the values. The parameter key typically looks like ENABLE_PASSWORD_CACHING. 

	.EXAMPLE
	Get-XMClientProperty  #returns all properties

	.EXAMPLE
	Get-XMClientProperty -key "ENABLE_PASSWORD_CACHING"

	#>
	[CmdletBinding()]
	param(
		[parameter(ValueFromPipelineByPropertyName)][string]$key = $null
	)

	Begin {
		if((checkSession) -eq $false){
			break
		}
	}

	Process {
		$result = getObject -url ( "/clientproperties/" + $key )
		return $result.allClientProperties
	}
}

function Remove-XMServerProperty {
	<#
	.SYNOPSIS
	Removes a server property. 

	.DESCRIPTION
	Removes a server property. This command accepts pipeline input.  

	.PARAMETER name
	Specify the name of the propery to remove. This parameter is mandatory. 

	.EXAMPLE
	remove-XMserverproperty -name "xms.something.something"
	#>
	[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
    param(
        [parameter(ValueFromPipelineByPropertyName,mandatory)][string[]]$name            
    )
	Begin {
		if((checkSession) -eq $false){
			break
		}
	}

    Process {
		if ($PSCmdlet.ShouldProcess($name)) {
			Write-Verbose ("Deleting " + $name)
			deleteObject -url "/serverproperties" -target $name
        }
    }
}

function New-XMServerProperty {
	<#
	.SYNOPSIS
	Create a new server property.  

	.DESCRIPTION
	Creates a new server property. All parameters are required.   

	.PARAMETER name
	Specify the name of the property. The parameter name typically looks like xms.publicapi.static.timeout. 

	.PARAMETER value
	Specify the value of the property. The value set during creation becomes the default value. 

	.PARAMETER displayName
	Specify a the display name.  

	.PARAMETER description
	Specify a the description. 

	.EXAMPLE
	new-xmserverProperty  -name "xms.something.something" -value "indeed" -displayName "something" -description "a something property."

	#>
	[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]

	param(
		[parameter(ValueFromPipelineByPropertyName,mandatory)][string]$name,
		[parameter(ValueFromPipelineByPropertyName,mandatory)][string]$value,
		[parameter(ValueFromPipelineByPropertyName,mandatory)][string]$displayName,
		[parameter(ValueFromPipelineByPropertyName,mandatory)][string]$description
	)

	Begin {
		if((checkSession) -eq $false){
			break
		}
	}

	Process {
		if ($PSCmdlet.ShouldProcess($name)) {
			$request.method = "POST"
			$request.url = "https://" + $XMSServer + ":" + $XMSServerPort + "/xenmobile/api/v1/serverproperties" 
			$request.header = @{ 'auth_token' = $XMSAuthtoken ;
								 'Content-Type' = 'application/json' }
			$request.body = @{  name = $name;
								value = $value;
								displayName = $displayName;
								description = $description;
							}
			submitToServer $request
		}
	}    
}

function Set-XMServerProperty {
	<#
	.SYNOPSIS
	Sets the server for server properties. 

	.DESCRIPTION
	Changes the value of an existing server property.  

	.PARAMETER name
	Specify the name of the property to change. The parameter name typically looks like xms.publicapi.static.timeout. 

	.PARAMETER value
	Specify the new value of the property. 

	.PARAMETER displayName
	Specify a new display name. This parameter is optional. If not specified the existing display name is used. 

	.PARAMETER description
	Specify a new description. This parameter is optional. If not specified the existing description is used. 

	.EXAMPLE
	set-xmserverProperty -name "xms.publicapi.static.timeout" -value "45"

	#>
	[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
	param(
		[parameter(ValueFromPipelineByPropertyName,mandatory)][string]$name,
		[parameter(ValueFromPipelineByPropertyName,mandatory)][string]$value,
		[parameter(ValueFromPipelineByPropertyName)][string]$displayName = $null,
		[parameter(ValueFromPipelineByPropertyName)][string]$description = $null
	)

	Begin {
		if((checkSession) -eq $false){
			break
		}
	}

	Process { 
		if ($PSCmdlet.ShouldProcess($name)) {
			if (!$displayName) {
				$displayName = (get-xmserverproperty -name $name).displayName
			}
			if (!$description) {
				$description = (get-xmserverproperty -name $name).description
			}
			$request.method = "PUT"
			$request.url = "https://" + $XMSServer + ":" + $XMSServerPort + "/xenmobile/api/v1/serverproperties" 
			$request.header = @{ 'auth_token' = $XMSAuthtoken ;
								 'Content-Type' = 'application/json' }
			$request.body = @{  name = $name;
								value = $value;
								displayName = $displayName;
								description = $description;
							}
			submitToServer $request
		} 
	}
}

function Get-XMServerProperty {
	<#
	.SYNOPSIS
	Queries the server for server properties. 

	.DESCRIPTION
	Queries the server for server properties. Without any parameters, this command will return all properties. 

	.PARAMETER name
	Specify the parameter for which you want to get the values. The parameter name typically looks like xms.publicapi.static.timeout. 

	.EXAMPLE
	get-xmserverProperty  #returns all properties

	.EXAMPLE
	get-xmserverProperty -name "xms.publicapi.static.timeout"

	#>
	[CmdletBinding()]

	param(
		[parameter(ValueFromPipeline)][string]$name = $null,
		[parameter(dontshow)][bool]$skipCheck = $false
	)

	Begin {
		if (!$skipCheck) {
			Write-Verbose "Checking the session state"
			if((checkSession) -eq $false){
				break
			}		
		} 
		else {
			Write-Verbose "The session check is skipped."
		}
	}    
	Process { 
		Write-Verbose "Creating the Get-xmserverproperty request."
		$request.method = "POST"
		$request.url = "https://" + $XMSServer + ":" + $XMSServerPort + "/xenmobile/api/v1/serverproperties/filter" 
		$request.header = @{ 'auth_token' = $XMSAuthtoken ;
							 'Content-Type' = 'application/json' }
		$request.body = @{  start = "0";
							limit = "1000";
							orderBy = "name";
							sortOrder =  "desc";
							searchStr = $name;
						}
		Write-Verbose "Submitting the get-xmsserverproperty request to the server"
		$results = submitToServer $request
		return $results.allEwProperties
	}
}

function Remove-XMDeviceProperty { 
	<#
	.SYNOPSIS
	deletes a properties for a device. 

	.DESCRIPTION
	Delete a property from a device. 
	WARNING: be careful when using this function. There is no safety check to ensure you don't accidentally delete things you shouldn't.

	.PARAMETER id
	Specify the ID of the device for which you want to get the properties. 

	.PARAMETER name
	Specify the name of the property. Such as "CORPORATE_OWNED" 

	.EXAMPLE
	Remove-XMDeviceProperty -id "8" -name "CORPORATE_OWNED"
	#>
	[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
	param(
		[parameter(ValueFromPipelineByPropertyName,mandatory)][string]$id,
		[parameter(ValueFromPipelineByPropertyName,mandatory)][string]$name
	)

	Begin {
		if((checkSession) -eq $false){
			break
		}
	}

	Process {
		if ($PSCmdlet.ShouldProcess($id)) {
			$property = Get-XMDeviceProperty -id $id | where-object { $_.name -eq $name } 
			Write-Verbose ("Property id for property: " + $name + " is " + $property.id   )
			deleteObject -url ("/device/property/" + $property.id) -target $null
		}
	}
}

function Set-XMDeviceProperty {
	<#
	.SYNOPSIS
	adds, changes a properties for a device. 

	.DESCRIPTION
	add or change properties for a device. Specify the device by ID, and property by name. To get the name of the property, search using get-xmdeviceproperties or get-xmdeviceknownproperties. 
	WARNING, avoid making changes to properties that are discovered by the existing processes. Use to to configure/set new properties. Most properties should not be changed this way.

	One property that is often changed is the ownership of a device. That property is called "CORPORATE_OWNED". Value '0' means BYOD, '1' means corporate and for unknown the property doesn't exist. 

	.PARAMETER id
	Specify the ID of the device for which you want to get the properties. 

	.PARAMETER name
	Specify the name of the property. Such as "CORPORATE_OWNED" 

	.PARAMETER value
	Specify the value of the property. 

	.EXAMPLE
	set-xmdeviceproperty -id "8" -name "CORPORATE_OWNED" -value "1"
	#>
	[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
	param(
        [parameter(ValueFromPipelineByPropertyName,mandatory)][string]$id,
        [parameter(ValueFromPipelineByPropertyName,mandatory)][string]$name,
        [parameter(ValueFromPipelineByPropertyName,mandatory)][string]$value      
    )

	Begin {
		if((checkSession) -eq $false){
			break
		}
	}

    Process {
        if ($PSCmdlet.ShouldProcess($id)) {
            $body = @{
                name = $name;
                value = $value
            }
            postObject -url ("/device/property/" + $id) -target $body    
        }
    }
}

function Get-XMDevicePolicy {
	<#
	.SYNOPSIS
	Displays the policies applies to a particular device.   

	.DESCRIPTION
	This command will list the policies applied to a particular device. 
	 
	 .PARAMETER id
	Specify the ID of the device. Use Get-XMDevice to find the id of each device.  

	.EXAMPLE
	Get-XMDevicePolicy -id "8" 

	#> 
	[CmdletBinding()]

	param(
		[parameter(ValueFromPipelineByPropertyName,mandatory)][string]$id
	)

	Begin {
		if((checkSession) -eq $false){
			break
		}
	}
	
	Process {
		$result = getObject -url ( "/device/" + $id + "/policies")
		return $result.policies
	}
}

function Get-XMDeviceSoftwareInventory { 
	<#
	.SYNOPSIS
	Displays the application inventory of a particular device.   

	.DESCRIPTION
	This command will list all installed applications as far as the server knows. Apps managed by the server are always included, other apps (such as personal apps) are only included if an inventory policy is deployed to the device. 

	.PARAMETER id
	Specify the ID of the device. Use Get-XMDevice to find the id of each device.  

	.EXAMPLE
	Get-XMDeviceSoftwareInventory -id "8" 

	#>
	[CmdletBinding()]
	param(
		[parameter(ValueFromPipelineByPropertyName,mandatory)][string]$id
	)

	Begin {
		if((checkSession) -eq $false){
			break
		}
	}

	Process {
		$result = getObject -url ( "/device/" + $id + "/softwareinventory" )
		return $result.softwareInventories
	}
}

function Get-XMDeviceInfo {
	<#
	.SYNOPSIS
	Displays the properties of a particular device.   

	.DESCRIPTION
	This command will output all properties, settings, configurations, certificates etc of a given device. This is typically an extensive list that may need to be further filtered down.
	This command aggregates a lot of information available through other commands as well. 

	.PARAMETER id
	Specify the ID of the device. Use Get-XMDevice to find the id of each device.  

	.EXAMPLE
	Get-XMDeviceInfo -id "8" 

	#> 
	[CmdletBinding()]
	param(
		[parameter(ValueFromPipelineByPropertyName,mandatory)][string]$id
	)
	Begin {
		if((checkSession) -eq $false){
			break
		}
	}
	Process {
		$result = getObject -url ( "/device/" + $id )
		return $result.device
	}
}

function Get-XMDeviceApps {
	<#
	.SYNOPSIS
	Displays all XenMobile store apps installed on a device, whether or ot the app was installed from the XenMobile Store 

	.DESCRIPTION
	This command will display all apps from the XenMobile Store installed on a device. This includes apps that were installed by the user themselves without selecting it from the XenMobile store. Thus is includes apps that are NOT managed but listed as available to the device.
	For apps that are NOT managed, an inventory policy is required to detect them. 

	This command is useful to find out which of the XenMobile store apps are installed (whether or not they are managed or installed from the XenMobile store).  

	.PARAMETER id
	Specify the ID of the device. Use Get-XMDevice to find the id of each device.  

	.EXAMPLE
	Get-XMDeviceApps -id "8" 

	#>
	[CmdletBinding()]

	param(
		[parameter(ValueFromPipelineByPropertyName,mandatory)][string]$id
	)

	Begin {
		if((checkSession) -eq $false){
			break
		}
	}

	Process {
		$result = getObject -url ( "/device/" + $id + "/apps" )
		return $result.applications
    }
}

function Get-XMDeviceManagedApps {
	<#
	.SYNOPSIS
	Displays the XMS managed apps for a given device specified by id. Managed Apps include those apps installed from the XenMobile Store.  

	.DESCRIPTION
	This command displays all managed applications on a particular device. Managed applications are those applications that have been installed from the XenMobile Store. 
	If a public store app is installed through policy on a device where the app is already installed, the user is given the option to have XMS manage the app. In that case, the app will be included in the output of this command. 
	If the user chooses not to let XMS manage the App, it will not be included in the output of this command. the Get-XMDeviceApps will still list that app. 

	.PARAMETER id
	Specify the ID of the device. Use Get-XMDevice to find the id of each device.  

	.EXAMPLE
	Get-XMDeviceManagedApps -id "8" 

	#>
	[CmdletBinding()]
    param(
		[parameter(ValueFromPipelineByPropertyName,mandatory)][string]$id      
    )
	Begin {
		if((checkSession) -eq $false){
			break
		}
	}

    Process {
		$result = getObject -url ( "/device/" + $id + "/managedswinventory" )
		return $result.softwareinventory
    }
}

function Remove-XMDevice {
	<#
	.SYNOPSIS
	Removes a device from the XMS server and database. 

	.DESCRIPTION
	Removes a devices from the XMS server. Requires the id of the device. 

	.PARAMETER id
	The id parameter identifies the device. You can get the id by searching for the correct device using get-device. 

	.EXAMPLE
	remove-xmdevice -id "21" 

	.EXAMPLE
	get-xmdevice -user "ward@citrix.com | %{ remove-xmdevice -id $_.id }
	#>
	[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
	param(
		[parameter(ValueFromPipeLineByPropertyName,mandatory)][string[]]$id
	)

	Begin {
		if((checkSession) -eq $false){
			break
		}
	}

	Process {
		if ($PSCmdlet.ShouldProcess($id)) {
			deleteObject -url "/device" -target $id
		}
	}
}

function Remove-XMUser {
	<#
	.SYNOPSIS
	Removes a user from the XMS server and database. 

	.DESCRIPTION
	Removes a user from the XMS server. Requires username. 

	.PARAMETER username
	The username parameter identifies the user. 

	.EXAMPLE
	remove-xmuser -username "user@local.domain" 	
	#>
	[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
	param(
		[parameter(ValueFromPipeLineByPropertyName,mandatory)][string]$username
	)

	Begin {
		if((checkSession) -eq $false){
			break
		}
	}

	Process {
		if ($PSCmdlet.ShouldProcess($username)) {
			deleteObject -url "/localusersgroups/deletelocalusers" -target $username
		}
	}
}

function Get-XMUsers {
	<#
	.SYNOPSIS
	Gets users from the XMS server and database. 

	.DESCRIPTION
	Gets users from the XMS server. 

	.PARAMETER filter
	The filter parameter is optional to search and get users. 

	.EXAMPLE
	get-xmusers -filter "search string"
	#>
	[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
	param(
		[parameter()][string]$filter,
		[parameter()][string]$search,
		[parameter()][boolean]$GetAll = $false,
		[parameter()][int]$StartIndex = 0,
		[parameter()][int]$ResultSetSize = 500
	)

	Begin {
		if((checkSession) -eq $false){
			break
		}
	}

	Process {	
		$usersCount = 0
		$userList = $null
		do
		{
			$result = search -url ( "/localusersgroups/filter" ) -criteria $search -ResultSetSize $ResultSetSize -filterIds $filter -startIndex $StartIndex
			$mesg = ($results.users | ConvertTo-Json)
			if(!($mesg -eq $null)){
				Write-Verbose $mesg
			}
			$usersCount = $result.users.count
			$StartIndex += $ResultSetSize
			$userList += $result.users
		}while($usersCount -eq $ResultSetSize -and $GetAll -eq $true)
		
		return $userList
	}
}

function Get-XMUser {
	<#
	.SYNOPSIS
	Gets a user from the XMS server and database. 

	.DESCRIPTION
	Gets a user from the XMS server. Requires the username.

	.PARAMETER user
	The user parameter identifies the username. 

	.EXAMPLE
	get-xmuser -username "ward@citrix.com
	#>
	[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
	param(
		[parameter(ValueFromPipeLineByPropertyName,mandatory)][string]$username
	)

	Begin {
		if((checkSession) -eq $false){
			break
		}
	}

	Process {
		$result = search -url ( "/localusersgroups/filter" ) -criteria $username -ResultSetSize 1
		$mesg = ($result.users | ConvertTo-Json)
		if(!($mesg -eq $null)){
			Write-Verbose $mesg
		}
		return $result.users
	}
}

function Update-XMDevice {
	<#
	.SYNOPSIS
	Sends a deploy command to the selected device. A deploy will trigger a device to check for updated policies. 

	.DESCRIPTION
	Sends a deploy command to the selected device. 

	.PARAMETER id
	This parameter specifies the id of the device to target. This can be pipelined from a search command. 

	.EXAMPLE
	update-xmdevice -id "24" 

	.EXAMPLE
	get-xmdevice -user "aford@corp.vanbesien.com" | update-xmdevice

	#>

	[CmdletBinding()]
	param(
		[parameter(ValueFromPipelineByPropertyName,mandatory=$true)][int[]]$id
	)

	Begin {
		if((checkSession) -eq $false){
			break
		}
	}
	
	Process {
		$message = "This will send an update to device " + $id     
		postObject -url "/device/refresh" -target $id  
	}
}

function Invoke-XMDeviceWipe {
	<#
	.SYNOPSIS
	Sends a device wipe command to the selected device.

	.DESCRIPTION
	Sends a device wipe command. this is similar to a factory reset

	.PARAMETER id
	This parameter specifies the id of the device to wipe. This can be pipelined from a search command. 

	.EXAMPLE
	invoke-xmdevicewipe -id "24" 

	.EXAMPLE
	get-xmdevice -user "ward@citrix.com" | invoke-xmdevicewipe

	#>
	[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
	param(
		[parameter(ValueFromPipelineByPropertyName,mandatory=$true)][int[]]$id
	)

	Begin {
		if((checkSession) -eq $false){
			break
		}
	}

	Process {
		if ($PSCmdlet.ShouldProcess($id)) {
			postObject -url "/device/wipe" -target $id
		}
	}
}

function Invoke-XMDeviceSelectiveWipe {
	<#
	.SYNOPSIS
	Sends a selective device wipe command to the selected device.

	.DESCRIPTION
	Sends a selective device wipe command. This removes all policies and applications installed by the server but leaves the rest of the device alone.

	.PARAMETER id
	This parameter specifies the id of the device to wipe. This can be pipelined from a search command. 

	.EXAMPLE
	invoke-XMDeviceSelectiveWipe -id "24" 

	.EXAMPLE
	Get-XMDevice -user "ward@citrix.com" | invoke-XMDeviceSelectiveWipe

	#>
	[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]

	param(
		[parameter(ValueFromPipelineByPropertyName,mandatory=$true)][int[]]$id
	)

	Begin {
		if((checkSession) -eq $false){
			break
		}
	}

	Process {
		if ($PSCmdlet.ShouldProcess($id)) {            
			postObject -url "/device/selwipe" -target $id
		}
	}
}

function Get-XMDeviceDeliveryGroups {
	<#
	.SYNOPSIS
	Displays the delivery groups for a given device specified by id.

	.DESCRIPTION
	This command lets you find all the delivery groups that apply to a particular device. You search based the ID of the device.
	To find the device id, use Get-XMDevice.

	.PARAMETER id
	Specify the ID of the device. Use Get-XMDevice to find the id of each device.  

	.EXAMPLE
	Get-XMDeviceDeliveryGroups -id "8" 

	#>
	[CmdletBinding()]

    param(
		[parameter(ValueFromPipelineByPropertyName,mandatory)][string]$id      
    )

	Begin {
		if((checkSession) -eq $false){
			break
		}
	}

    Process {
		$result = getObject -url ( "/device/" + $id + "/deliverygroups" )
		return $result.deliveryGroups
    }
}

function Get-XMDeviceActions {
	<#
	.SYNOPSIS
	Displays the smart actions applied to a given device specified by id.

	.DESCRIPTION
	This command lets you find all the smart actions available that apply to a particular device. You search based the ID of the device.
	To find the device id, use Get-XMDevice.

	.PARAMETER id
	Specify the ID of the device. Use Get-XMDevice to find the id of each device.  

	.EXAMPLE
	Get-XMDeviceActions -id "8" 

	#>
	[CmdletBinding()]

	param(
		[parameter(ValueFromPipelineByPropertyName,mandatory)][string]$id
	)

	Begin {
		if((checkSession) -eq $false){
			break
		}
	}

	Process {
		$result = getObject -url ( "/device/" + $id + "/actions" )
		return $result
	}    
}

function Get-XMDevice {
	<#
	.SYNOPSIS
	Basic search function to find devices

	.DESCRIPTION
	Search function to find devices. If you specify the user parameter, you get all devices for a particular user. 
	The devices are returned as an array of objects, each object representing a single device. 

	.PARAMETER criteria
	Specify a search criteria. If you specify a UPN or username, all enrollments for the username will be returned. 
	It also possible to provide other values such as serial number to find devices. Effectively, anything that will work in the 'search' field in the GUI will work here as well.    

	.PARAMETER filter
	Specify a filter to further reduce the amount of data returned.  The syntax is "[filter]". For example, to see all MDM device enrolments, use "[device.mode.mdm.managed,device.mode.mdm.unmanaged]".
	Here are some of the filters: 
	device.mode.enterprise.managed
	device.mode.enterprise.unmanaged
	device.mode.mdm.managed
	device.mode.mdm.unmanaged
	device.mode.mam.managed
	device.mode.mam.unmanaged 
	device.status.jailbroken
	device.status.as.gateway.blocked
	device.status.out.of.compliance
	device.status.samsung.knox.not.attested
	device.status.enrollment.program.registred (for Apple DEP)
	group#/group/ActiveDirectory/citrix/com/XM-Users@_fn_@normal   (for users in AD group XM-users in the citrix.com AD)
	device.platform.ios
	device.platform.android
	device.platform#10.0.1@_fn_@device.platform.ios.version   (for iOS device, version 10.0.1)
	device.ownership.byod
	device.ownership.corporate
	device.ownership.unknown
	device.inactive.time.30.days
	device.inactive.time.more.than.30.days
	device.inactive.time.8.hours

	.PARAMETER ResultSetSize
	By default only the first 1000 records are returned. Specify the resultsetsize to get more records returned. 

	.EXAMPLE
	get.XMDevice -criteria "ward@citrix.com" -filter "[device.mode.enterprise.managed]"

	#>

	[CmdletBinding()]
	param(
		[parameter(ValueFromPipeline)][string]$criteria,
		[parameter()][string]$filter = "[]",
		[parameter()][boolean]$GetAll = $false,
		[parameter()][int]$StartIndex = 0,
		[parameter()][int]$ResultSetSize = 999
		
	)

	Begin {
		if((checkSession) -eq $false){
			break
		}
	}

	Process {
		$devicesCount = 0
		$deviceList = $null
		do
		{
			$result = search -url "/device/filter" -criteria $criteria -filterIds $filter -ResultSetSize $ResultSetSize -startIndex $StartIndex
			$mesg = ($results.filteredDevicesDataList | ConvertTo-Json)
			if(!($mesg -eq $null)){
				Write-Verbose $mesg
			}
			$devicesCount = $result.filteredDevicesDataList.count
			$StartIndex += $ResultSetSize
			$deviceList += $result.filteredDevicesDataList
		}while($devicesCount -eq $ResultSetSize -and $GetAll -eq $true)
		
		return $deviceList
		
	}
}

function Get-XMEnrollment {
	<#
	.SYNOPSIS
	Searches for enrollment invitations. 

	.DESCRIPTION
	Searches for enrollment invitations. Without parameters, it will return all invitations. You can get all enrollment for a given user by specifing a the criteria parameter. 

	.PARAMETER user
	Specify the user if you wnat enrollments for a particular user account. If you specify a UPN or username, all enrollments for the username will be returned. 

	.PARAMETER filter
	This parameter allows you to filter results based on other criteria. The syntax is "[filter]". For example, to see all BYOD device enrolments, use "[enrollment.ownership.byod]". 
	Multiple values can be specified, separated by a comma. Following are some of the filters that can be used (not an exhaustive list). 
	enrollment.ownership.byod
	enrollment.ownership.corporate
	enrollment.ownership.unknown
	enrollment.invitationMode#classic@_fn_@invitation
	enrollment.invitationMode#invitation@_fn_@invitation
	enrollment.invitationStatus.ios
	enrollment.invitationPlatform.android
	enrollment.invitationStatus.redeemed
	enrollment.invitationStatus.expired
	enrollment.invitationStatus.pending
	enrollment.invitationStatus.failed

	.PARAMETER ResultSetSize
	By default, only the first 1000 entries will be returned. You can override this value to get more (or less) results. 

	.EXAMPLE
	get-XMenrollment 

	.EXAMPLE
	Get-XMEnrollment -user "ward@citrix.com"

	.EXAMPLE
	Get-XMEnrollment -filter "[enrollment.invitationStatus.expired]"

	#>

	[CmdletBinding()]
	param(
		[parameter(ValueFromPipelineByPropertyName)][string]$user,
		[parameter()][string]$filter = "[]",
		[parameter()][int]$ResultSetSize = 999
	)

	Begin {
		if((checkSession) -eq $false){
			break
		}
	}
	
	Process {
		$searchresult = search  -url "/enrollment/filter" -criteria $user -filterIds $filter -ResultSetSize $ResultSetSize
		$resultset =  $searchresult.enrollmentFilterResponse.enrollmentList.enrollments
		$resultset | Add-Member -NotePropertyName AgentNotificationTemplateName -NotePropertyValue $searchresult.enrollmentFilterResponse.enrollmentList.enrollments.notificationTemplateCategories.notificationTemplate.name
		return $resultset
	}
}

function New-XMEnrollment {
	<#
	.SYNOPSIS
	This command will create an enrollment for the specified user.


	.DESCRIPTION
	Use this command to create enrollments. You can pipe parameters into this command from another command. 
	The command currently does not process notifications. It will return an object with details of the enrollment including the URL and PIN code (called secret).  

	.PARAMETER user
	The user parameter specifies the target user.
	This parameter is required. This is either the UPN or sAMAccountName depending on what you are using in your environment. 

	.PARAMETER OS
	The OS parameter specifies the type of operating system. Options are iOS, SHTP.
	For android, use SHTP. This parameter is required. 

	.PARAMETER phoneNumber
	This is the phone number notifications will be sent to. The parameter is optional but without it no SMS notifications are sent. 

	.PARAMETER carrier
	Specify the carrier to use. This is optional and only required in case multiple cariers and SMS gateway have been configured. 

	.PARAMETER deviceBindingType
	You can specify either SERIALNUMBER, IMEI or UDID as the device binding paramater. This defaults to SERIALNUMBER. 
	This parameter is only useful if you also specify the deviceBindingData. 

	.PARAMETER deviceBindingData
	By specifying devicebindingdata you can link an enrollment invitation to a specific device. Use the deviceBindingType to specify what you will use, 
	and specify the value here. For example, to bind to a serial number set the deviceBindingType to SERIALNUMBER and provide the serialnumber as the value of deviceBindingData. 

	.PARAMETER ownership
	This parameter specifies the ownership of the device. Values are either CORPORATE or BYOD or NO_BINDING.
	Default value is NO_BINDING. 

	.PARAMETER mode
	This parameter specifes the type of enrollment mode you are using. Make sure the specified mode is enable on the server otherwise, an error will be thrown. 
	Default mode is classic. The select enrollment type must be enabled on the server. 
	Options are: 
	classic: username and password (default)
	high_security: generates an invitation URL, one time PIN and requires used to provide username, PIN and password.
	invitation: generates an invitation URL
	invitation_pin: generates and invitation and one time PIN
	invitation_pwd: generates an inivation and will request the user's password during enrollment 
	username_pin: generates a one time PIN and requires users to login with that pin and the username
	two_factor: generates an invitation url, a one time PIN and requires the user to login with, password and PIN. 

	.PARAMETER agentTemplate
	Specify the template to use when sending a notification to the user to download Secure Hub. The default is blank. 
	This value is case sensitive. To find out the correct name, create an enrollment invitation in the XMS GUI and view the available options for the notification template. 

	.PARAMETER invitationTemplate
	Specify the template to use when sending a notification to the user to with the enrollment URL. The default is blank. 
	This value is case sensitive. To find out the correct name, create an enrollment invitation in the XMS GUI and view the available options for the notification template. 

	.PARAMETER pinTemplate
	Specify the template to use when sending a notification for the one time PIN to the user. The default is blank. 
	This value is case sensitive. To find out the correct name, create an enrollment invitation in the XMS GUI and view the available options for the notification template. 

	.PARAMETER confirmationTemplate
	Specify the template to use when sending a notification to the user at completion of the enrollment. The default is blank. 
	This value is case sensitive. To find out the correct name, create an enrollment invitation in the XMS GUI and view the available options for the notification template. 

	.PARAMETER notifyNow
	Specify if you want to send notifications to the user. Value is either "true" or "false" (default.) 

	.EXAMPLE
	new-xmenrollment -user "ward@citrix.com" -OS "iOS" -ownership "BYOD" -mode "invitation_url"

	.EXAMPLE
	import-csv -path users.csv | new-enrollment -OS iOS -ownership BYOD

	This will read a CSV file and create an enrolment for each of the entries.

	#>
	[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]

	param(
		[parameter(ValueFromPipeLineByPropertyName,ValueFromPipeLine,mandatory=$true)][string]$user,
		[parameter(ValueFromPipeLineByPropertyName,ValueFromPipeLine,mandatory=$true)][ValidateSet("iOS","SHTP")][string]$OS,
		[parameter(valueFromPipelineByPropertyName)]$phoneNumber = $null,
		[parameter(valueFromPipelineByPropertyName)]$carrier = $null,
		[parameter(valueFromPipelineByPropertyName)][ValidateSet("SERIALNUMBER","UDID","IMEI")]$deviceBindingType = "SERIALNUMBER",
		[parameter(valueFromPipelineByPropertyName)]$deviceBindingData = $null,
		[parameter(ValueFromPipeLineByPropertyName,ValueFromPipeLine)][ValidateSet("CORPORATE","BYOD","NO_BINDING")][string]$ownership = "NO_BINDING",
		[parameter(valueFromPipeLineByPropertyName)][ValidateSet("classic","high_security","invitation","invitation_pin","invitation_pwd","username_pin",
		"two_factor")]$mode = "classic",
		[parameter(ValueFromPipeLineByPropertyName)]$agentTemplate = $null,
		[parameter(ValueFromPipeLineByPropertyName)]$invitationTemplate = $null,
		[parameter(ValueFromPipeLineByPropertyName)]$pinTemplate = $null,
		[parameter(ValueFromPipeLineByPropertyName)]$confirmationTemplate = $null,
		[parameter(ValueFromPipeLineByPropertyName)][ValidateSet("true","false")]$notifyNow = "false",
		[switch]$force
	)

	Begin {
		if((checkSession) -eq $false){
			break
		}
		
		$RejectAll = $false
		$ConfirmAll = $false
	}

	Process {
		if ($force -or $PSCmdlet.ShouldContinue("Do you want to continue?","Creating enrollment for '$user'",[ref]$ConfirmAll,[ref]$RejectAll)  ) {
			$body = @{	
						platform = $OS
						deviceOwnership = $ownership
						mode = @{ name = $mode }
						userName = $user
						notificationTemplateCategories = @(
							@{  
								notificationTemplate = @{ name = $agentTemplate }
								category = "ENROLLMENT_AGENT"
							} 
							@{ 
								notificationTemplate = @{  name = $invitationTemplate }
								category = "ENROLLMENT_URL" 
							} 
							@{ 
								notificationTemplate = @{ name = $pinTemplate }
								category = "ENROLLMENT_PIN"
							} 
							@{ 
								notificationTemplate = @{ name = $confirmationTemplate }
								category = "ENROLLMENT_CONFIRMATION" 
							}
						)
						phoneNumber = $phoneNumber
						carrier = $carrier
						deviceBindingType = $deviceBindingType
						deviceBindingData = $deviceBindingData
						notifyNow = $notifyNow
			}
			Write-Verbose "Created enrollment request object for submission to server. "
			$enrollmentResult = postObject -url "/enrollment" -target $body -ErrorAction Stop
			Write-Verbose "Enrollment invitation submitted."
			# the next portion of the function will download additional information about the enrollment request
			# this is pointless if the invitation was not correctly created due to an error with the request. 
			# Hence, we only run this, if there is an actual invitation in the enrollmentResult value. 
			if ($enrollmentResult -ne $null) {
				Write-Verbose "An enrollment invication was created. Searching for additional details. "
				$searchresult = search -url "/enrollment/filter" -criteria $enrollmentResult.token
				$enrollment = $searchresult.enrollmentFilterResponse.enrollmentList.enrollments
				$enrollment | Add-Member -NotePropertyName url -NotePropertyValue $enrollmentResult.url
				$enrollment | Add-Member -NotePropertyName message -NotePropertyValue $enrollmentResult.message
				$enrollment | Add-Member -NotePropertyName AgentNotificationTemplateName -NotePropertyValue $searchresult.enrollmentFilterResponse.enrollmentList.enrollments.notificationTemplateCategories.notificationTemplate.name
				return $enrollment 
			} 
			else {
				Write-Verbose "The server was unable to create an enrollment invitation for '$user'. Common causes are connectivity issues, as well as errors in the information supplied such as username, template names etc. Ensure all values in the request are correct." -ForegroundColor Yellow
			}
		}
	}
}

Export-ModuleMember -Function Get-XMClientProperty
Export-ModuleMember -Function Get-XMDevice
Export-ModuleMember -Function Get-XMDeviceActions
Export-ModuleMember -Function Get-XMDeviceApps
Export-ModuleMember -Function Get-XMDeviceDeliveryGroups
Export-ModuleMember -Function Get-XMDeviceInfo
Export-ModuleMember -Function Get-XMDeviceManagedApps
Export-ModuleMember -Function Get-XMDevicePolicy
Export-ModuleMember -Function Get-XMDeviceProperty
Export-ModuleMember -Function Get-XMDeviceSoftwareInventory
Export-ModuleMember -Function Get-XMEnrollment
Export-ModuleMember -Function Get-XMServerProperty
Export-ModuleMember -Function Invoke-XMDeviceSelectiveWipe
Export-ModuleMember -Function Invoke-XMDeviceWipe
Export-ModuleMember -Function New-XMClientProperty
Export-ModuleMember -Function New-XMEnrollment
Export-ModuleMember -Function New-XMServerProperty
Export-ModuleMember -Function New-XMSession
Export-ModuleMember -Function Remove-XMClientProperty
Export-ModuleMember -Function Remove-XMDevice
Export-ModuleMember -Function Remove-XMDeviceProperty
Export-ModuleMember -Function Remove-XMServerProperty
Export-ModuleMember -Function Set-XMClientProperty
Export-ModuleMember -Function Set-XMDeviceProperty
Export-ModuleMember -Function Set-XMServerProperty
Export-ModuleMember -Function Update-XMDevice
Export-ModuleMember -Function Get-XMUser
Export-ModuleMember -Function Get-XMUsers
Export-ModuleMember -Function Remove-XMUser
Export-ModuleMember -Function convertFrom-MisinterpretedUtf8
Export-ModuleMember -Function checkSession
