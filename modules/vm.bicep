// ============================================================================
// Virtual Machine モジュール
// Virtual Machine、NIC を定義
// ============================================================================

@description('Azure リージョン')
param location string

@description('プロジェクト名')
param projectName string

@description('環境名')
param environment string

@description('VM 名')
param vmName string

@description('VM サイズ')
param vmSize string

@description('管理者ユーザー名')
param adminUsername string

@description('SSH 公開鍵')
@secure()
param sshPublicKey string

@description('サブネット ID')
param subnetId string

@description('Public IP を有効化するか')
param enablePublicIp bool = false

@description('cloud-init データ')
param cloudInitData string = ''

@description('SSH 秘密鍵 (Test VM 用、オプション)')
@secure()
param sshPrivateKey string = ''

// ============================================================================
// Public IP Address (オプション)
// ============================================================================

resource pip 'Microsoft.Network/publicIPAddresses@2023-09-01' = if (enablePublicIp) {
  name: 'pip-${vmName}-${environment}'
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: '${vmName}-${environment}-${uniqueString(resourceGroup().id)}'
    }
  }
}

// ============================================================================
// Network Interface
// ============================================================================

resource nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: 'nic-${vmName}-${environment}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: enablePublicIp ? {
            id: pip.id
          } : null
        }
      }
    ]
  }
}

// ============================================================================
// Virtual Machine
// ============================================================================

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      customData: !empty(cloudInitData) ? base64(cloudInitData) : null
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'minimal-arm64'
        version: 'latest'
      }
      osDisk: {
        name: '${vmName}-osdisk'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        diskSizeGB: 30
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

// ============================================================================
// Custom Script Extension (SSH 秘密鍵の配置用、Test VM のみ)
// ============================================================================

resource customScript 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = if (!empty(sshPrivateKey)) {
  parent: vm
  name: 'CustomScript'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    protectedSettings: {
      commandToExecute: 'echo "${base64(sshPrivateKey)}" | base64 -d > /home/${adminUsername}/.ssh/vm-ssh-key && sed -i -e \'$a\\\' /home/${adminUsername}/.ssh/vm-ssh-key && chmod 600 /home/${adminUsername}/.ssh/vm-ssh-key && chown ${adminUsername}:${adminUsername} /home/${adminUsername}/.ssh/vm-ssh-key'
    }
  }
}

// ============================================================================
// 出力
// ============================================================================

output vmId string = vm.id
output nicId string = nic.id
output privateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
output publicIpAddress string = enablePublicIp ? pip!.properties.ipAddress : ''
output publicIpFqdn string = enablePublicIp ? pip!.properties.dnsSettings.fqdn : ''
