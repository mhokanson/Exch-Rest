function New-EXRFolder
{
	[CmdletBinding()]
	param (
		[Parameter(Position = 0, Mandatory = $true)]
		[string]
		$MailboxName,
		
		[Parameter(Position = 1, Mandatory = $false)]
		[psobject]
		$AccessToken,
		
		[Parameter(Position = 2, Mandatory = $true)]
		[string]
		$ParentFolderPath,
		
		[Parameter(Position = 3, Mandatory = $true)]
		[string]
		$DisplayName
		
	)
	Begin
	{
		if ($AccessToken -eq $null)
		{
			$AccessToken = Get-EXRAccessToken -MailboxName $MailboxName
		}
		$ParentFolder = Get-EXRFolderFromPath -FolderPath $ParentFolderPath -AccessToken $AccessToken -MailboxName $MailboxName
		if ($ParentFolder -ne $null)
		{
			$HttpClient = Get-EXRHTTPClient -MailboxName $MailboxName
			$RequestURL = $ParentFolder.FolderRestURI + "/childfolders"
			$NewFolderPost = "{`"DisplayName`": `"" + $DisplayName + "`"}"
			write-host $NewFolderPost
			return Invoke-EXRRestPOST -RequestURL $RequestURL -HttpClient $HttpClient -AccessToken $AccessToken -MailboxName $MailboxName -Content $NewFolderPost
			
		}
		
		
	}
}