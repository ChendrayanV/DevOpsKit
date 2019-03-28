Set-StrictMode -Version Latest

class AzureDevOpsResourceResolver: Resolver
{
    [SVTResource[]] $SVTResources = @();
    [string] $ResourcePath;
    [string] $organizationName
    hidden [string[]] $ProjectNames = @();
    hidden [string[]] $BuildNames = @();
    hidden [string[]] $ReleaseNames = @();
    [int] $SVTResourcesFoundCount=0;
    AzureDevOpsResourceResolver([string]$organizationName,$ProjectNames,$BuildNames,$ReleaseNames,$ScanAllArtifacts): Base($organizationName)
	{
        $this.organizationName = $organizationName

        

        if(-not [string]::IsNullOrEmpty($ProjectNames))
        {
			$this.ProjectNames += $this.ConvertToStringArray($ProjectNames);

			if ($this.ProjectNames.Count -eq 0)
			{
				throw [SuppressedException] "The parameter 'ProjectNames' does not contain any string."
			}
        }	

        if(-not [string]::IsNullOrEmpty($BuildNames))
        {
			$this.BuildNames += $this.ConvertToStringArray($BuildNames);
			if ($this.BuildNames.Count -eq 0)
			{
				throw [SuppressedException] "The parameter 'BuildNames' does not contain any string."
			}
        }

        if(-not [string]::IsNullOrEmpty($ReleaseNames))
        {
			$this.ReleaseNames += $this.ConvertToStringArray($ReleaseNames);
			if ($this.ReleaseNames.Count -eq 0)
			{
				throw [SuppressedException] "The parameter 'ReleaseNames' does not contain any string."
			}
        }

        if($ScanAllArtifacts)
        {
            $this.ProjectNames = "*"
            $this.BuildNames = "*"
            $this.ReleaseNames = "*"
        }        
    }

    [void] LoadAzureResources()
	{
        
        #Call APIS for Organization,User/Builds/Releases/ServiceConnections 
        #Select Org/User by default...
        $svtResource = [SVTResource]::new();
        $svtResource.ResourceName = $this.organizationName;
        $svtResource.ResourceType = "AzureDevOps.Organization";
        $svtResource.ResourceId = "Organization/$($this.organizationName)/"
        $svtResource.ResourceTypeMapping = ([SVTMapping]::AzSKDevOpsResourceMapping |
                                        Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                                        Select-Object -First 1)
        $this.SVTResources +=$svtResource


        $svtResource = [SVTResource]::new();
        $svtResource.ResourceName = $this.organizationName;
        $svtResource.ResourceType = "AzureDevOps.User";
        $svtResource.ResourceId = "Organization/$($this.organizationName)/User"
        $svtResource.ResourceTypeMapping = ([SVTMapping]::AzSKDevOpsResourceMapping |
                                        Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                                        Select-Object -First 1)
        $this.SVTResources +=$svtResource

        #Get project resources
        if($this.ProjectNames.Count -gt 0)
        {
            $this.PublishCustomMessage("Querying api for resources to be scanned. This may take a while...");

            $this.PublishCustomMessage("Getting project configurations...");

            $apiURL = "https://dev.azure.com/{0}/_apis/projects?api-version=4.1" -f $($this.SubscriptionContext.SubscriptionName);
            $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL) ;

            $responseObj  | Where-Object {  (($this.ProjectNames -contains $_.name) -or ($this.ProjectNames -eq "*"))  } | ForEach-Object {
                $projectName = $_.name
                $svtResource = [SVTResource]::new();
                $svtResource.ResourceName = $_.name;
                $svtResource.ResourceGroupName = $this.organizationName
                $svtResource.ResourceType = "AzureDevOps.Project";
                $svtResource.ResourceId = $_.url
                $svtResource.ResourceTypeMapping = ([SVTMapping]::AzSKDevOpsResourceMapping |
                                                Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                                                Select-Object -First 1)
                
                $this.SVTResources +=$svtResource

                if($this.ProjectNames -ne "*")
                {
                    $this.PublishCustomMessage("Getting service endpoint configurations...");
                }
                
                $serviceEndpointURL = "https://dev.azure.com/{0}/{1}/_apis/serviceendpoint/endpoints?api-version=4.1-preview.1" -f $($this.organizationName),$($projectName);
                $serviceEndpointObj = [WebRequestHelper]::InvokeGetWebRequest($serviceEndpointURL)
                
                if(([Helpers]::CheckMember($serviceEndpointObj,"count") -and $serviceEndpointObj[0].count -gt 0) -or  (($serviceEndpointObj | Measure-Object).Count -gt 0 -and [Helpers]::CheckMember($serviceEndpointObj[0],"name")))
                {
                    $svtResource = [SVTResource]::new();
                    $svtResource.ResourceName = "ServiceConnections";
                    $svtResource.ResourceGroupName =$_.name;
                    $svtResource.ResourceType = "AzureDevOps.ServiceConnection";
                    $svtResource.ResourceId = "Organization/$($this.organizationName)/Project/ServiceConnection"
                    $svtResource.ResourceTypeMapping = ([SVTMapping]::AzSKDevOpsResourceMapping |
                                                    Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                                                    Select-Object -First 1)
                    $this.SVTResources +=$svtResource
                }

                if($this.BuildNames.Count -gt 0 )
                {
                    if($this.ProjectNames -ne "*")
                    {
                        $this.PublishCustomMessage("Getting build configurations...");
                    }

                    if($this.BuildNames -eq "*")
                    {
                        $buildDefnURL = "https://dev.azure.com/{0}/{1}/_apis/build/definitions?api-version=4.1" -f $($this.SubscriptionContext.SubscriptionName), $_.name;
                        $buildDefnsObj = [WebRequestHelper]::InvokeGetWebRequest($buildDefnURL) 
                        if(([Helpers]::CheckMember($buildDefnsObj,"count") -and $buildDefnsObj[0].count -gt 0) -or  (($buildDefnsObj | Measure-Object).Count -gt 0 -and [Helpers]::CheckMember($buildDefnsObj[0],"name")))
                        {
                            $buildDefnsObj  | ForEach-Object {
                                $svtResource = [SVTResource]::new();
                                $svtResource.ResourceName = $_.name;
                                $svtResource.ResourceGroupName =$_.project.name;
                                $svtResource.ResourceType = "AzureDevOps.Build";
                                $svtResource.ResourceId = $_.url
                                $svtResource.ResourceTypeMapping = ([SVTMapping]::AzSKDevOpsResourceMapping |
                                                                Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                                                                Select-Object -First 1)
                                $this.SVTResources +=$svtResource
                            }
                        }
                    }
                    else
                    {
                        $this.BuildNames | ForEach-Object {
                            $buildName = $_
                            $buildDefnURL = "https://{0}.visualstudio.com/{1}/_apis/build/definitions?name={2}&api-version=5.1-preview.7" -f $($this.SubscriptionContext.SubscriptionName),$projectName, $buildName;
                            $buildDefnsObj = [WebRequestHelper]::InvokeGetWebRequest($buildDefnURL) 
                            if(([Helpers]::CheckMember($buildDefnsObj,"count") -and $buildDefnsObj[0].count -gt 0) -or  (($buildDefnsObj | Measure-Object).Count -gt 0 -and [Helpers]::CheckMember($buildDefnsObj[0],"name")))
                            {
                                $buildDefnsObj  | ForEach-Object {
                                    $svtResource = [SVTResource]::new();
                                    $svtResource.ResourceName = $_.name;
                                    $svtResource.ResourceGroupName =$_.project.name;
                                    $svtResource.ResourceType = "AzureDevOps.Build";
                                    $svtResource.ResourceId = $_.url
                                    $svtResource.ResourceTypeMapping = ([SVTMapping]::AzSKDevOpsResourceMapping |
                                                                    Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                                                                    Select-Object -First 1)
                                    $this.SVTResources +=$svtResource
                                }
                            }
                        }
                    }
                           
                }

                if($this.ReleaseNames.Count -gt 0)
                {
                    if($this.ProjectNames -ne "*")
                    {
                        $this.PublishCustomMessage("Getting release configurations...");
                    }
                    if($this.ReleaseNames -eq "*")
                    {
                        $releaseDefnURL = "https://vsrm.dev.azure.com/{0}/{1}/_apis/release/definitions?api-version=4.1-preview.3" -f $($this.SubscriptionContext.SubscriptionName), $projectName;
                        $releaseDefnsObj = [WebRequestHelper]::InvokeGetWebRequest($releaseDefnURL);
                        if(([Helpers]::CheckMember($releaseDefnsObj,"count") -and $releaseDefnsObj[0].count -gt 0) -or  (($releaseDefnsObj | Measure-Object).Count -gt 0 -and [Helpers]::CheckMember($releaseDefnsObj[0],"name")))
                        {
                            $releaseDefnsObj  | ForEach-Object {
                                $svtResource = [SVTResource]::new();
                                $svtResource.ResourceName = $_.name;
                                $svtResource.ResourceGroupName =$projectName;
                                $svtResource.ResourceType = "AzureDevOps.Release";
                                $svtResource.ResourceId = $_.url
                                $svtResource.ResourceTypeMapping = ([SVTMapping]::AzSKDevOpsResourceMapping |
                                                                Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                                                                Select-Object -First 1)
                                $this.SVTResources +=$svtResource
                            }
                        }
                    }
                    else
                    {
                        $this.ReleaseNames | ForEach-Object {
                            $resleaseName = $_
                            $releaseDefnURL = "https://{0}.vsrm.visualstudio.com/_apis/Contribution/HierarchyQuery/project/{1}?api-version=5.0-preview.1" -f $($this.SubscriptionContext.SubscriptionName), $projectName;
                            $inputbody = "{
                                'contributionIds': [
                                    'ms.vss-releaseManagement-web.search-definitions-data-provider'
                                ],
                                'dataProviderContext': {
                                    'properties': {
                                        'searchText': '$resleaseName',
                                        'sourcePage': {
                                            'routeValues': {
                                                'project': '$projectName'
                                            }
                                        }
                                    }
                                }
                            }" | ConvertFrom-Json
                            
                            $releaseDefnsObj = [WebRequestHelper]::InvokePostWebRequest($releaseDefnURL,$inputbody);
                            if(([Helpers]::CheckMember($releaseDefnsObj,"dataProviders") -and $releaseDefnsObj.dataProviders."ms.vss-releaseManagement-web.search-definitions-data-provider") -and [Helpers]::CheckMember($releaseDefnsObj.dataProviders."ms.vss-releaseManagement-web.search-definitions-data-provider","releaseDefinitions") )
                            {
                                $releaseDefnsObj.dataProviders."ms.vss-releaseManagement-web.search-definitions-data-provider".releaseDefinitions  | ForEach-Object {
                                    $svtResource = [SVTResource]::new();
                                    $svtResource.ResourceName = $_.name;
                                    $svtResource.ResourceGroupName =$projectName;
                                    $svtResource.ResourceType = "AzureDevOps.Release";
                                    $svtResource.ResourceId = $_.url
                                    $svtResource.ResourceTypeMapping = ([SVTMapping]::AzSKDevOpsResourceMapping |
                                                                    Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                                                                    Select-Object -First 1)
                                    $this.SVTResources +=$svtResource
                                }
                        }

                        }
                    }
                }        
            }
        }
        $this.SVTResourcesFoundCount = $this.SVTResources.Count
    }
}