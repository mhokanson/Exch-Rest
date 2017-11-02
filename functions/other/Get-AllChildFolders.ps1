﻿function Get-AllChildFolders
{
	param (
		[Parameter(Position = 0, Mandatory = $true)]
		[PSCustomObject]
		$Folder,
		
		[Parameter(Position = 1, Mandatory = $false)]
		[psobject]
		$AccessToken,
		
		[Parameter(Position = 2, Mandatory = $false)]
		[PSCustomObject]
		$PropList
	)
	Begin
	{
		if ($AccessToken -eq $null)
		{
			$AccessToken = Get-AccessToken -MailboxName $MailboxName
		}
		$HttpClient = Get-HTTPClient($MailboxName)
		$EndPoint = Get-EndPoint -AccessToken $AccessToken -Segment "users"
		$RequestURL = $Folder.FolderRestURI + "/childfolders/?`$Top=1000"
		if ($PropList -ne $null)
		{
			$Props = Get-ExtendedPropList -PropertyList $PropList -AccessToken $AccessToken
			$RequestURL += "`&`$expand=SingleValueExtendedProperties(`$filter=" + $Props + ")"
		}
		do
		{
			$JSONOutput = Invoke-RestGet -RequestURL $RequestURL -HttpClient $HttpClient -AccessToken $AccessToken -MailboxName $MailboxName -TrackStatus $true
			foreach ($ChildFolder in $JSONOutput.Value)
			{
				$ChildFolder | Add-Member -NotePropertyName FolderPath -NotePropertyValue ($Folder.FolderPath + "\" + $ChildFolder.DisplayName)
				$folderId = $ChildFolder.Id.ToString()
				Add-Member -InputObject $ChildFolder -NotePropertyName FolderRestURI -NotePropertyValue ($EndPoint + "('$MailboxName')/MailFolders('$folderId')")
				Invoke-EXRParseExtendedProperties -Item $ChildFolder
				Write-Output $ChildFolder
				if ($ChildFolder.ChildFolderCount -gt 0)
				{
					if ($PropList -ne $null)
					{
						Get-AllChildFolders -Folder $ChildFolder -AccessToken $AccessToken -PropList $PropList
					}
					else
					{
						Get-AllChildFolders -Folder $ChildFolder -AccessToken $AccessToken
					}
				}
			}
			$RequestURL = $JSONOutput.'@odata.nextLink'
		}
		while (![String]::IsNullOrEmpty($RequestURL))
		
		
	}
}