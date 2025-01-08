<#
.SYNOPSIS
    A script to find the ScopeId for an IP address, retrieve its associated MAC address,
    and reserve the IP on a DHCP server.

.DESCRIPTION
    This script interacts with a DHCP server to:
    - Find the ScopeId of a specified IP address.
    - Retrieve the MAC address of the device currently leasing the IP.
    - Reserve the IP address for the device on the DHCP server.

.EXAMPLE
    # Example usage:
    # Assume you are managing a corporate DHCP server and want to reserve an IP address
    # for a web server used in your GitHub project. The web server currently has a DHCP lease.
    
    # Step 1: Run the script and provide the DHCP server name and the IP address to reserve.
    # Step 2: The script will find the ScopeId, retrieve the MAC address, and reserve the IP.

    # Example invocation:
    $dhcp_server = "DHCP01"
    $reservation_ip = "192.168.1.100"
    .\Reserve-IP.ps1 -dhcp_server $dhcp_server -reservation_ip $reservation_ip
#>

function Find-ScopeId {
    param (
        [string]$dhcp_server,
        [string]$reservation_ip
    )

    Write-Host "Connecting to DHCP server $dhcp_server to find ScopeId for IP $reservation_ip..." -ForegroundColor Cyan

    try {
        $scopes = Get-DhcpServerv4Scope -ComputerName $dhcp_server

        if (-not $scopes) {
            Write-Host "No scopes found on DHCP server $dhcp_server." -ForegroundColor Yellow
            throw "DHCP server has no defined scopes."
        }

        foreach ($scope in $scopes) {
            $startIP = [System.Net.IPAddress]::Parse($scope.StartRange).GetAddressBytes()
            $endIP = [System.Net.IPAddress]::Parse($scope.EndRange).GetAddressBytes()
            $reservationIP = [System.Net.IPAddress]::Parse($reservation_ip).GetAddressBytes()

            $isInRange = $true
            for ($i = 0; $i -lt $startIP.Length; $i++) {
                if ($reservationIP[$i] -lt $startIP[$i] -or $reservationIP[$i] -gt $endIP[$i]) {
                    $isInRange = $false
                    break
                }
            }

            if ($isInRange) {
                Write-Host "Found matching ScopeId: $($scope.ScopeId) for IP $reservation_ip." -ForegroundColor Green
                return $scope.ScopeId
            }
        }

        Write-Host "No matching ScopeId found for IP $reservation_ip." -ForegroundColor Red
        return $null
    } catch {
        Write-Host "Error: $_" -ForegroundColor Red
        throw "Error finding ScopeId: $_"
    }
}

function Get-MacAddressForIP {
    param (
        [string]$dhcp_server,
        [string]$reservation_ip
    )

    try {
        Write-Host "Checking DHCP leases on server $dhcp_server for IP $reservation_ip..." -ForegroundColor Cyan
        
        $lease = Get-DhcpServerv4Lease -ComputerName $dhcp_server -IPAddress $reservation_ip

        if ($lease -and $lease.ClientId) {
            Write-Host "Found MAC address $($lease.ClientId) for IP $reservation_ip." -ForegroundColor Green
            return $lease.ClientId
        } else {
            Write-Host "No lease found for IP $reservation_ip on server $dhcp_server." -ForegroundColor Yellow
            return $null
        }
    } catch {
        Write-Host "Error: $_" -ForegroundColor Red
        throw "Error retrieving MAC address for IP $reservation_ip: $_"
    }
}

function Reserve-IP {
    param (
        [string]$dhcp_server,
        [string]$reservation_ip,
        [string]$scope_id,
        [string]$client_mac
    )

    try {
        Write-Host "Reserving IP $reservation_ip on DHCP server $dhcp_server for client with MAC address $client_mac..." -ForegroundColor Cyan
        
        Add-DhcpServerv4Reservation -ComputerName $dhcp_server -ScopeId $scope_id -IPAddress $reservation_ip -ClientId $client_mac -Description "Reserved for GitHub project"

        Write-Host "IP address $reservation_ip has been reserved successfully!" -ForegroundColor Green
    } catch {
        Write-Host "Failed to reserve IP address. Error: $_" -ForegroundColor Red
    }
}

try {
    if (-not $dhcp_server) {
        $dhcp_server = Read-Host "Enter the DHCP server name or IP address"
    }

    if (-not $reservation_ip) {
        $reservation_ip = Read-Host "Enter the IP address to find the ScopeId for"
    }

    $scopeId = Find-ScopeId -dhcp_server $dhcp_server -reservation_ip $reservation_ip

    if ($scopeId) {
        Write-Output "The ScopeId for IP $reservation_ip is $scopeId."

        $client_mac = Get-MacAddressForIP -dhcp_server $dhcp_server -reservation_ip $reservation_ip

        if ($client_mac) {
            Reserve-IP -dhcp_server $dhcp_server -reservation_ip $reservation_ip -scope_id $scopeId -client_mac $client_mac
        } else {
            Write-Host "Unable to reserve IP address $reservation_ip because no MAC address was found." -ForegroundColor Red
        }
    } else {
        Write-Output "No matching ScopeId was found for IP $reservation_ip."
    }
} catch {
    Write-Output "Failed to retrieve ScopeId or make reservation. Error: $_"
}
