function Invoke-RestGet {
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, Mandatory = $true)]
        [string]
        $RequestURL,
		
        [Parameter(Position = 1, Mandatory = $true)]
        [String]
        $MailboxName,
		
        [Parameter(Position = 2, Mandatory = $true)]
        [System.Net.Http.HttpClient]
        $HttpClient,
		
        [Parameter(Position = 3, Mandatory = $false)]
        [psobject]
        $AccessToken,
		
        [Parameter(Position = 4, Mandatory = $false)]
        [switch]
        $NoJSON,
		
        [Parameter(Position = 5, Mandatory = $false)]
        [bool]
        $TrackStatus = $false,
		
        [Parameter(Position = 6, Mandatory = $false)]
        [String]
        $ProcessMessage,

        [Parameter(Position = 7, Mandatory = $false)]
        [switch]
        $BasicAuthentication,

        [Parameter(Position = 8, Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credentials,

        [Parameter(Position = 9, Mandatory = $false)]
        [switch]
        $NoRetry,

        [Parameter(Position = 9, Mandatory = $false)]
        [switch]
        $RawResponse,

        [Parameter(Position = 10, Mandatory = $false)]
        [String]
        $TimeZone,
 
       [Parameter(Position = 11, Mandatory = $false)]
        [String]
        $BodyFormat,

        [Parameter(Position = 12, Mandatory = $false)]
        [switch]
        $IdToken

    )
    process {
        if ($BasicAuthentication.IsPresent) {
            $psString = $Credentials.UserName.ToString() + ":" + $Credentials.GetNetworkCredential().password.ToString()
            $psbyteArray = [System.Text.Encoding]::ASCII.GetBytes($psString);
            $HttpClient.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue("Basic", [System.Convert]::ToBase64String($psbyteArray));
        }
        else {
            #Check for expired Token
            $minTime = new-object DateTime(1970, 1, 1, 0, 0, 0, 0, [System.DateTimeKind]::Utc);
            $expiry = $minTime.AddSeconds($AccessToken.expires_on)
            if ($expiry -le [DateTime]::Now.ToUniversalTime().AddMinutes(10)) {
                if ([bool]($AccessToken.PSobject.Properties.name -match "refresh_token")) {
                    $refreshToken = $true
                    $CachedAccessToken = Get-ProfiledToken -MailboxName $MailboxName
                    if ($CachedAccessToken -ne $null) {
                        if ($CachedAccessToken.Mailbox -eq $AccessToken.Mailbox) {
                            $minTime = new-object DateTime(1970, 1, 1, 0, 0, 0, 0, [System.DateTimeKind]::Utc);
                            $expiry = $minTime.AddSeconds($CachedAccessToken.expires_on)
                            if ($expiry -le [DateTime]::Now.ToUniversalTime().AddMinutes(10)) {
                                $refreshToken = $true
                            }
                            else {
                                $refreshToken = $false
                                $AccessToken = $CachedAccessToken
                            }
                        }
                    } 
                    if ($refreshToken) {
                        write-host "Refresh Token"
                        $AccessToken = Invoke-RefreshAccessToken -MailboxName $MailboxName -AccessToken $AccessToken
                    }	
                }
                else {
                    if ($AccessToken.ADAL) {
                        if($AccessToken.ExpiresOn.DateTime -le [DateTime]::Now.ToUniversalTime().AddMinutes(10)) {
                            $Context = New-Object Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext($AccessToken.Authority)
                            $token = ($Context.AcquireTokenSilentAsync($AccessToken.resource,$AccessToken.clientid)).Result
                            if($token.AccessToken -ne $AccessToken.AccessToken){
                                write-host "Refreshed Token ADAL"
                                if ([bool]($token.PSobject.Properties.name -match "AccessToken")) {
                                    #$AdalToken.access_token = 
                                    Add-Member -InputObject $token -NotePropertyName access_token -NotePropertyValue (Get-ProtectedToken -PlainToken $AccessToken.AccessToken) -Force
                                }
                                Add-Member -InputObject $token -NotePropertyName clientid -NotePropertyValue $AccessToken.clientid
                                Add-Member -InputObject $token -NotePropertyName ADAL -NotePropertyValue $True
                                Add-Member -InputObject $token -NotePropertyName redirectUrl -NotePropertyValue $AccessToken.redirectUrl
                                Add-Member -InputObject $token -NotePropertyName resource -NotePropertyValue $AccessToken.resource
                                Add-Member -InputObject $token -NotePropertyName mailbox -NotePropertyValue $AccessToken.mailbox
                                Add-Member -InputObject $token -NotePropertyName resourceCache -NotePropertyValue $AccessToken.resourceCache
                                if(![String]::IsNullOrEmpty($AccessToken.TenantId)){
                                    Add-Member -InputObject $token -NotePropertyName TenantId -NotePropertyValue $AccessToken.TenantId
                                }
                                Add-Member -InputObject $token -NotePropertyName Cached -NotePropertyValue $true
                                $HostDomain = (New-Object system.net.Mail.MailAddress($AccessToken.mailbox)).Host.ToLower()
                                if(!$Script:TokenCache[$AccessToken.resourceCache].ContainsKey($HostDomain)){			
                                    $Script:TokenCache[$AccessToken.resourceCache].Add($HostDomain,$token)
                                }
                                else{
                                    $Script:TokenCache[$AccessToken.resourceCache][$HostDomain] = $token
                                }
                                $AccessToken = $token
                            }
                        }
                    }else{
                        throw "App Token has expired"
                    }                    
                }
				
            }
            if ($Script:TraceRequest) {
                write-host $RequestURL
            }
            if($IdToken.IsPresent){
                $HttpClient.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", (ConvertFrom-SecureStringCustom -SecureToken $AccessToken.id_token));
            }else{
                $HttpClient.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", (ConvertFrom-SecureStringCustom -SecureToken $AccessToken.access_token));
            }
            
        }
        if([String]::IsNullOrEmpty($TimeZone)){
            $TimeZone = [TimeZoneInfo]::Local.Id;
        }
        $HttpClient.DefaultRequestHeaders.Add("Prefer", ("outlook.timezone=`"" + $TimeZone + "`""))
	if($BodyFormat){
		$HttpClient.DefaultRequestHeaders.Add("Prefer", ("outlook.body-content-type=`"" + $BodyFormat + "`""))

	}		
        $ClientResult = $HttpClient.GetAsync($RequestURL)
        $exProgress = 0
        if ($TrackStatus) {
            While ($ClientResult.Status -eq [System.Threading.Tasks.TaskStatus]::Running -bor $ClientResult.Status -eq [System.Threading.Tasks.TaskStatus]::WaitingForActivation) {
                if ([String]::IsNullOrEmpty($ProcessMessage)) {
                    Write-Progress -Activity ("Executing Request " + $RequestURL) -PercentComplete $exProgress;
                }
                else {
                    Write-Progress -Activity ($ProcessMessage) -PercentComplete $exProgress;
                }
                Start-Sleep -Milliseconds 200
                $exProgress += .2
            }
            Write-Progress -Activity "Executing Request" -Completed
        }
        if ($ClientResult.Result.StatusCode -ne [System.Net.HttpStatusCode]::OK) {
            if ($ClientResult.Result.StatusCode -ne [System.Net.HttpStatusCode]::Created) {
                write-Host ($ClientResult.Result)
            }
            if ($ClientResult.Result.Content -ne $null) {
                Write-Host ($ClientResult.Result.Content.ReadAsStringAsync().Result);
            }
        }
        if ($ClientResult.Result.StatusCode -eq [System.Net.HttpStatusCode]::GatewayTimeout) {
            if (!$NoRetry.IsPresent) {
                write-host("Sleep and retry in 5 Seconds")
                Start-Sleep -Seconds 5
                Invoke-RestGet -RequestURL $RequestURL -MailboxName $MailboxName -HttpClient $HttpClient -AccessToken $AccessToken -NoRetry -NoJSON:$NoJSON.IsPresent -ProcessMessage $ProcessMessage
            }
        }
        if (!$ClientResult.Result.IsSuccessStatusCode) {
            Write-Host ("Error making REST Get " + $ClientResult.Result.StatusCode + " : " + $ClientResult.Result.ReasonPhrase)
            Write-Host ("RequestURL : " + $RequestURL)
        }
        else {
            if ($RawResponse.IsPresent) {
				return $ClientResult
            }
            else {
                if ($NoJSON) {
                    return $ClientResult.Result.Content
                }
                else {
                    $JsonObject = ExpandPayload($ClientResult.Result.Content.ReadAsStringAsync().Result)
                    #$JsonObject = ConvertFrom-Json -InputObject  $ClientResult.Result.Content.ReadAsStringAsync().Result
                    if ([String]::IsNullOrEmpty($ClientResult)) {
                        write-host "No Value returned"
                    }
                    else {
                        if ($JsonObject -ne $null) {
                            Add-Member -InputObject $JsonObject -NotePropertyName DateTimeRESTOperation -NotePropertyValue (Get-Date).ToString("s")
                        }					
                        return $JsonObject
                    }
				
                }
            }

			
        }
		
    }
}