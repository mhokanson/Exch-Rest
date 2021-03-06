function Get-EXRAttachments
{
	[CmdletBinding()]
	param (
		[Parameter(Position = 0, Mandatory = $false)]
		[string]
		$MailboxName,
		
		[Parameter(Position = 1, Mandatory = $true)]
		[string]
		$ItemURI,
		
		[Parameter(Position = 2, Mandatory = $false)]
		[psobject]
		$AccessToken,
		
		[Parameter(Position = 3, Mandatory = $false)]
		[switch]
		$MetaData,
		
		[Parameter(Position = 4, Mandatory = $false)]
		[string]
		$SelectProperties
	)
	Begin
	{
		if($AccessToken -eq $null)
        {
            $AccessToken = Get-ProfiledToken -MailboxName $MailboxName  
            if($AccessToken -eq $null){
                $AccessToken = Get-EXRAccessToken -MailboxName $MailboxName       
            }                 
        }
         if([String]::IsNullOrEmpty($MailboxName)){
            $MailboxName = $AccessToken.mailbox
        } 
		if ([String]::IsNullorEmpty($SelectProperties))
		{
			$SelectProperties = "`$select=Name,ContentType,Size,isInline,ContentType"
		}
		else
		{
			$SelectProperties = "`$select=" + $SelectProperties
		}
		$HttpClient = Get-HTTPClient -MailboxName $MailboxName
		$RequestURL = $ItemURI + "/Attachments?" + $SelectProperties
		do
		{
			$JSONOutput = Invoke-RestGet -RequestURL $RequestURL -HttpClient $HttpClient -AccessToken $AccessToken -MailboxName $MailboxName
			foreach ($Message in $JSONOutput.Value)
			{
				Add-Member -InputObject $Message -NotePropertyName AttachmentRESTURI -NotePropertyValue ($ItemURI + "/Attachments('" + $Message.Id + "')")
				Write-Output $Message
			}
			$RequestURL = $JSONOutput.'@odata.nextLink'
		}
		while (![String]::IsNullOrEmpty($RequestURL))
		
		
	}
}
