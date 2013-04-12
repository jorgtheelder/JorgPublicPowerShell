Write-Host 'GetLastLogon.ps1 - jorgie@missouri.edu'
#Gets the LastLogon value for any user or computer in the forest
#You must be able to talke to the ADWS port on all DCs.

function Get-ADLastLogon {
  param (
    [Parameter(Mandatory=$true,ValueFromPipeLine=$true)]
    [string]
    $sAMAccountName
  )

  #added for PS2 users, PS3 autoimports the AD module
  if(!(Get-Module ActiveDirectory)) {
    Import-Module ActiveDirectory -ErrorAction Stop;
  }

  $firstDC = (get-addomaincontroller).HostName.ToLower();
  'Starting with a DC in the current domain: {0}' -f $firstDC;
  $root = '{0}:3268' -f $firstDC;

  Write-Host ('Finding user on GC port of DC: {0}' -f $root);  
  $u = Get-ADObject -Filter { sAMAccountName -eq $sAMAccountName } -Properties CanonicalName, DisplayName -Server $root -SearchScope Subtree;

  if($u -ne $null) {
    Write-Host ('Found CanonicalName: {0}' -f $u.CanonicalName);
    $domain = $u.CanonicalName.SubString(0,$u.CanonicalName.IndexOf('/'));

    #use -Discover to find a domain controller to use with -Filter on to find ALL domain controllers
    Write-Host ('Asking the current domain for a single DC in {0} domain' -f $domain);
    $oneDC = (Get-ADDomainController -DomainName $domain -Discover).HostName.ToLower();

    Write-Host ('Asking {0} for a full list of DCs in {1}' -f $oneDC, $domain);
    $allDCs = Get-ADDomainController -Filter { Domain -eq $domain } -Server $oneDC

    #build a nice output object for the pipeline
    $result = New-Object Object | Select-Object sAMAccountName, DomainController, LastLogin, LastLoginReadable;
    $result.sAMAccountName = $sAMAccountName;

    Write-Host ("Found {0} DCs in {1}, gettin LastLogon from each one`r`n" -f $allDCs.Count, $domain);
    $allDCs |
      ForEach-Object {
        $dc = $_.HostName.ToLower();
        $dcName = $($_.Name); #using $() to dereference the object
        $cu = Get-ADObject -Filter { sAMAccountName -eq $sAMAccountName } -Properties LastLogon -Server $dc;
        if($cu -eq $null) {
          Write-Host ('Could not find user on DC: {0} ({1})' -f $dcName, $dc);
        } else {
          $lld = $cu.LastLogon;
          $llr = [datetime]::FromFileTime($lld).ToString();
          if($lld -gt $result.LastLogin) {
            $result.LastLogin = $lld;
            $result.LastLoginReadable = $llr;
            $result.DomainController = $dcName;
          }
          if($lld -gt 0) {
            Write-Host ("'{0}' last logged into {1} at '{2}'" -f $sAMAccountName, $dcName, $llr);
          } else {
            Write-Host ("'{0}' has never logged into '{1}'" -f $sAMAccountName, $dcName);
          }
        }
      }
    Write-Host ("`r`nThe most recient login for '{0}' was at '{1}' on '{2}'.`r`n" -f $result.sAMAccountName, $result.LastLoginReadable, $result.DomainController);
    $result;
  } else { Write-Host ('{0} not found!' -f $sAMAccountName); }
}

#calling it like this lets the function prompt for input if it needs to
if($args.Count -gt 0) {
  Get-ADLastLogon $args[0];
} else {
  Get-ADLastLogon;
}
