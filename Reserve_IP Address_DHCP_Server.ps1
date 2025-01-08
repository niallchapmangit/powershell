<#
.SYNOPSIS
    A PowerShell script to dynamically find the ScopeId and MAC address for an IP on a DHCP server and create a reservation.

.DESCRIPTION
    This script automates the process of reserving an IP address on a DHCP server. It:
    - Connects to the specified DHCP server.
    - Dynamically identifies the ScopeId associated with the IP address.
    - Retrieves the MAC address of the device leasing the IP.
    - Creates a reservation for the specified IP with an optional description.

.EXAMPLE
    # Usage Example 
    # This script can be used to automate IP reservations for your project's servers.

    # Step 1: Define the required parameters
    $dhcp_server = "DHCP01"
    $reservation_ip = "192.168.1.100"
    $description = "Reserved for project-server in GitHub project."

    # Step 2: Execute the script
    .\Reserve-DHCP.ps1 -dhcp_server $dhcp_server -reservation_ip $reservation_ip -description $description

    # Result: The script will connect to the DHCP server, find the relevant ScopeId, retrieve the MAC address, 
    # and create a reservation for the specified IP address. A success or error message will be displayed in JSON format.

    # You can include this script in your GitHub repository as part of a network automation project for your CV.
#>

param (
    [string]$dhcp_server,           # The DHCP Server
    [string]$reservation_ip,        # Current IP address to reserve
    [string]$description = "Reservation created via automation" # Optional description
)

function Connect-DhcpServer {
    param (
        [string]$dhcp_server
    )

    Write-Host "Connecting to DHCP server $dhcp_server..." -ForegroundColor Cyan
    try {
        $lease = Get-DhcpServerv4Lease -ComputerName $dhcp_server | Select-Object -First 1
        if (-not $lease) {
            throw "No leases found on DHCP server $dhcp_server."
        }
        Write-Host "Successfully connected to DHCP server $dhcp_server." -ForegroundColor Green
    } catch {
        throw "Failed to connect to DHCP server $dhcp_server. Error: $_"
    }
}

function Find-ScopeId {
    param (
        [string]$dhcp_server,
        [string]$reservation_ip
    )

    Write-Host "Finding ScopeId for IP $reservation_ip on server $dhcp_server..." -ForegroundColor Cyan

    try {
        $scopes = Get-DhcpServerv4Scope -ComputerName $dhcp_server
        if (-not $scopes) {
            throw "No scopes found on DHCP server $dhcp_server."
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

        throw "No matching ScopeId found for IP $reservation_ip."
    } catch {
        throw "Error finding ScopeId: $_"
    }
}

function Get-MacAddressForIP {
    param (
        [string]$dhcp_server,
        [string]$scope_id,
        [string]$reservation_ip
    )

    Write-Host "Retrieving MAC address for IP $reservation_ip in scope $scope_id..." -ForegroundColor Cyan

    try {
        $lease = Get-DhcpServerv4Lease -ComputerName $dhcp_server -ScopeId $scope_id | Where-Object { $_.IPAddress -eq $reservation_ip }

        if ($lease -and $lease.ClientId) {
            Write-Host "Found MAC address $($lease.ClientId) for IP $reservation_ip." -ForegroundColor Green
            return $lease.ClientId
        } else {
            throw "No DHCP lease found for IP address $reservation_ip in scope $scope_id."
        }
    } catch {
        throw "Error retrieving MAC address for IP $reservation_ip: $_"
    }
}

function Add-DhcpReservation {
    param (
        [string]$dhcp_server,
        [string]$scope_id,
        [string]$reservation_ip,
        [string]$mac_address,
        [string]$description
    )

    Write-Host "Creating reservation for IP $reservation_ip with MAC $mac_address in scope $scope_id..." -ForegroundColor Cyan

    try {
        Add-DhcpServerv4Reservation -ComputerName $dhcp_server -ScopeId $scope_id -IPAddress $reservation_ip -ClientId $mac_address -Description $description
        Write-Host "Reservation successfully created." -ForegroundColor Green

        return @{ reservation_ip = $reservation_ip; mac_address = $mac_address; scope_id = $scope_id; server = $dhcp_server }
    } catch {
        throw "Error creating DHCP reservation: $_"
    }
}

try {
    if (-not $reservation_ip -or -not $dhcp_server) {
        throw "All required parameters (dhcp_server, reservation_ip) must be provided."
    }

    Connect-DhcpServer -dhcp_server $dhcp_server

    $scope_id = Find-ScopeId -dhcp_server $dhcp_server -reservation_ip $reservation_ip

    $mac_address = Get-MacAddressForIP -dhcp_server $dhcp_server -scope_id $scope_id -reservation_ip $reservation_ip

    $reservation_details = Add-DhcpReservation -dhcp_server $dhcp_server -scope_id $scope_id -reservation_ip $reservation_ip -mac_address $mac_address -description $description

    $output = @{ status = "success"; message = "Reservation successfully created."; details = $reservation_details }
    Write-Output (ConvertTo-Json $output -Depth 10)
    exit 0
} catch {
    $output = @{ status = "failure"; message = "Failed to reserve the IP address."; error = $_.Exception.Message; details = @{ reservation_ip = $reservation_ip; server = $dhcp_server } }
    Write-Output (ConvertTo-Json $output -Depth 10)
    exit 1
}
