// ============================================================================
// ネットワークモジュール
// VNet、サブネット、NSG、VNet ピアリングを定義
// ============================================================================

@description('Azure リージョン')
param location string

@description('プロジェクト名')
param projectName string

@description('環境名')
param environment string

@description('VNet1 アドレス空間')
param vnet1AddressPrefix string

@description('VNet1 AppGW サブネットプレフィックス')
param vnet1AppGwSubnetPrefix string

@description('VNet2 アドレス空間')
param vnet2AddressPrefix string

@description('VNet2 VM サブネットプレフィックス')
param vnet2VmSubnetPrefix string

@description('VNet3 アドレス空間')
param vnet3AddressPrefix string

@description('VNet3 テストVM サブネットプレフィックス')
param vnet3VmSubnetPrefix string

// ============================================================================
// NSG: Application Gateway サブネット用
// ============================================================================

resource nsgAppGw 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-${projectName}-appgw-${environment}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP-Inbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-HTTPS-Inbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-GatewayManager-Inbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '65200-65535'
          sourceAddressPrefix: 'GatewayManager'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }
    ]
  }
}

// ============================================================================
// NSG: Backend VM1 サブネット用
// ============================================================================

resource nsgVm1 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-${projectName}-vm1-${environment}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP-From-AppGw'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: vnet1AppGwSubnetPrefix
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-SSH-From-TestVM'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: vnet3VmSubnetPrefix
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 200
          direction: 'Inbound'
        }
      }
    ]
  }
}

// ============================================================================
// NSG: Test VM サブネット用 (JIT により動的に管理)
// ============================================================================

resource nsgTest 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-${projectName}-test-${environment}'
  location: location
  properties: {
    securityRules: [
      // JIT により SSH ルールが動的に追加されるため、静的ルールは不要
      // 必要に応じて、JIT が無効な場合の代替ルールをここに追加可能
    ]
  }
}

// ============================================================================
// VNet1: Application Gateway 専用
// ============================================================================

resource vnet1 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: 'vnet-${projectName}-appgw-${environment}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnet1AddressPrefix
      ]
    }
    subnets: [
      {
        name: 'snet-appgw'
        properties: {
          addressPrefix: vnet1AppGwSubnetPrefix
          networkSecurityGroup: {
            id: nsgAppGw.id
          }
        }
      }
    ]
  }
}

// ============================================================================
// VNet2: Backend VM 用
// ============================================================================

resource vnet2 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: 'vnet-${projectName}-backend-${environment}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnet2AddressPrefix
      ]
    }
    subnets: [
      {
        name: 'snet-vm1'
        properties: {
          addressPrefix: vnet2VmSubnetPrefix
          networkSecurityGroup: {
            id: nsgVm1.id
          }
        }
      }
    ]
  }
}

// ============================================================================
// VNet3: テスト・管理用
// ============================================================================

resource vnet3 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: 'vnet-${projectName}-test-${environment}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnet3AddressPrefix
      ]
    }
    subnets: [
      {
        name: 'snet-test'
        properties: {
          addressPrefix: vnet3VmSubnetPrefix
          networkSecurityGroup: {
            id: nsgTest.id
          }
        }
      }
    ]
  }
}

// ============================================================================
// VNet Peering: VNet1 (AppGW) ↔ VNet2 (Backend)
// ============================================================================

resource peeringVnet1ToVnet2 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: vnet1
  name: 'peer-appgw-to-backend'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: vnet2.id
    }
  }
}

resource peeringVnet2ToVnet1 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: vnet2
  name: 'peer-backend-to-appgw'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: vnet1.id
    }
  }
}

// ============================================================================
// VNet Peering: VNet2 (Backend) ↔ VNet3 (Test)
// ============================================================================

resource peeringVnet2ToVnet3 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: vnet2
  name: 'peer-backend-to-test'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: vnet3.id
    }
  }
  dependsOn: [
    peeringVnet2ToVnet1 // VNet2 の他のピアリングが完了してから
  ]
}

resource peeringVnet3ToVnet2 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: vnet3
  name: 'peer-test-to-backend'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: vnet2.id
    }
  }
}

// ============================================================================
// 出力
// ============================================================================

output vnet1Id string = vnet1.id
output vnet2Id string = vnet2.id
output vnet3Id string = vnet3.id

output appGwSubnetId string = vnet1.properties.subnets[0].id
output vm1SubnetId string = vnet2.properties.subnets[0].id
output vmTestSubnetId string = vnet3.properties.subnets[0].id

output nsgAppGwId string = nsgAppGw.id
output nsgVm1Id string = nsgVm1.id
output nsgTestId string = nsgTest.id
