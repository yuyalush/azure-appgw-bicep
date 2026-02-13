# Azure Application Gateway デプロイガイド

このディレクトリには、Azure Application Gateway と VNet 構成シナリオの Bicep テンプレートが含まれています。

## 📁 ファイル構成

```
.
├── main.bicep                      # メインオーケストレーションファイル
├── main.bicepparam                 # パラメータファイル
├── README.md                       # このファイル
├── concept.md                      # アーキテクチャ設計ドキュメント
├── modules/
│   ├── network.bicep              # VNet、サブネット、NSG、ピアリング
│   ├── appgw.bicep                # Application Gateway
│   └── vm.bicep                   # Virtual Machine
└── cloud-init/
    ├── vm1-nginx.yaml             # Backend VM1 初期化スクリプト
    └── vmtest-tools.yaml          # Test VM 初期化スクリプト
```

## 🚀 デプロイ手順

### 1. SSH Key Pair の生成

```bash
# SSH キーペアを生成
ssh-keygen -t rsa -b 4096 -f ~/.ssh/vm-ssh-key -C "azureuser@azure-vms"

# 公開鍵の内容を確認
cat ~/.ssh/vm-ssh-key.pub

# (オプション) Azure Key Vault に秘密鍵を保存
az keyvault secret set \
  --vault-name <your-keyvault-name> \
  --name vm-ssh-private-key \
  --file ~/.ssh/vm-ssh-key
```

### 2. パラメータファイルの編集

`main.bicepparam` を開き、以下を設定してください:

```bicep
// SSH 公開鍵を設定 (必須)
param sshPublicKey = '<cat ~/.ssh/vm-ssh-key.pub の出力をここに貼り付け>'

// その他のパラメータは必要に応じて調整
param location = 'japaneast'
param environment = 'prod'
param projectName = 'appgw'
```

### 3. リソースグループの作成

```bash
az group create \
  --name rg-appgw-demo \
  --location japaneast
```

### 4. Bicep のデプロイ

```bash
# パラメータファイルを使用してデプロイ
az deployment group create \
  --resource-group rg-appgw-demo \
  --template-file main.bicep \
  --parameters main.bicepparam

# または、SSH 秘密鍵も一緒にデプロイする場合
az deployment group create \
  --resource-group rg-appgw-demo \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters sshPrivateKey="$(cat ~/.ssh/vm-ssh-key)"
```

### 5. デプロイ結果の確認

```bash
# 出力値を確認
az deployment group show \
  --resource-group rg-appgw-demo \
  --name <deployment-name> \
  --query properties.outputs

# または、JSON 形式で保存
az deployment group show \
  --resource-group rg-appgw-demo \
  --name <deployment-name> \
  --query properties.outputs > deployment-outputs.json
```

## 🧪 検証手順

### 1. JIT を使用して Test VM に接続

```bash
# Microsoft Defender for Cloud で JIT を有効化 (Azure Portal)
# または Azure CLI:
az security jit-policy create \
  --resource-group rg-appgw-demo \
  --location japaneast \
  --name jit-policy-vm-test \
  --virtual-machines "/subscriptions/<subscription-id>/resourceGroups/rg-appgw-demo/providers/Microsoft.Compute/virtualMachines/vm-test" \
  --ports '[{"number":22,"protocol":"*","allowed_source_address_prefix":"*","max_request_access_duration":"PT3H"}]'

# JIT アクセスをリクエスト
az vm open-port \
  --resource-group rg-appgw-demo \
  --name vm-test \
  --port 22 \
  --duration 180

# SSH 接続
ssh -i ~/.ssh/vm-ssh-key azureuser@<Test-VM-Public-IP>
```

### 2. Application Gateway のテスト

Test VM にログイン後、以下のテストを実施:

```bash
# デプロイ時の出力値から AppGW の Public IP を確認
APPGW_IP="<AppGW-Public-IP>"

# 自動テストスクリプトを実行
./test-appgw.sh $APPGW_IP

# または手動でテスト
curl http://$APPGW_IP
```

### 3. Backend VM1 への接続

```bash
# Test VM から Backend VM1 に SSH 接続
./connect-vm1.sh

# または直接接続
ssh -i ~/.ssh/vm-ssh-key azureuser@10.1.1.4

# VM1 で nginx の状態を確認
sudo systemctl status nginx
sudo tail -f /var/log/nginx/access.log
```

## 📊 リソース一覧

デプロイされるリソース:

| リソースタイプ | 名前 | 用途 |
|--------------|------|------|
| VNet | vnet-appgw-appgw-prod | Application Gateway 専用 |
| VNet | vnet-appgw-backend-prod | Backend VM 用 |
| VNet | vnet-appgw-test-prod | テスト・管理用 |
| Application Gateway | appgw-appgw-prod | HTTP/HTTPS ロードバランサー |
| VM | vm-web1 | Backend Web サーバー (nginx) |
| VM | vm-test | テスト・管理用 VM |
| Public IP | pip-appgw-appgw-prod | Application Gateway 用 |
| Public IP | pip-vm-test-prod | Test VM 用 (JIT 接続) |
| NSG | nsg-appgw-appgw-prod | AppGW サブネット用 |
| NSG | nsg-appgw-vm1-prod | VM1 サブネット用 |
| NSG | nsg-appgw-test-prod | Test VM サブネット用 (JIT 管理) |

## 🔒 セキュリティ設定

### JIT (Just-In-Time) VM Access

- **対象**: Test VM のみ
- **ポート**: SSH (22)
- **最大接続時間**: 3時間
- **設定場所**: Microsoft Defender for Cloud

### NSG ルール

- **AppGW サブネット**: HTTP (80), HTTPS (443), GatewayManager (65200-65535) を許可
- **VM1 サブネット**: AppGW からの HTTP (80)、Test VM からの SSH (22) を許可
- **Test VM サブネット**: JIT により動的に管理

## 🧹 リソースのクリーンアップ

```bash
# リソースグループごと削除
az group delete \
  --name rg-appgw-demo \
  --yes \
  --no-wait
```

## 💰 コスト見積もり

主なコスト要素:

- Application Gateway Standard_v2: ~$200-300/月
- VM (Standard_B2s) x 2: ~$30-40/月 x 2
- Public IP (Standard) x 2: ~$3/月 x 2
- VNet Peering: データ転送量に応じて
- Managed Disks: ~$5/月 x 2

**合計概算**: ~$280-400/月

## 📚 参考資料

- [Application Gateway ドキュメント](https://learn.microsoft.com/azure/application-gateway/)
- [VNet Peering ドキュメント](https://learn.microsoft.com/azure/virtual-network/virtual-network-peering-overview)
- [JIT VM Access ドキュメント](https://learn.microsoft.com/azure/defender-for-cloud/just-in-time-access-usage)
- [Bicep ドキュメント](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)

## 🐛 トラブルシューティング

### Backend Health が Unhealthy の場合

1. VM1 で nginx が起動しているか確認:
   ```bash
   ssh -i ~/.ssh/vm-ssh-key azureuser@10.1.1.4
   sudo systemctl status nginx
   ```

2. NSG ルールで AppGW からの通信が許可されているか確認

3. Application Gateway のヘルスプローブ設定を確認

### Test VM に SSH 接続できない場合

1. JIT アクセスが有効化されているか確認
2. JIT アクセスリクエストが承認されているか確認
3. 接続元 IP が許可されているか確認

### VNet ピアリングが動作しない場合

1. ピアリングのステータスが "Connected" になっているか確認
2. NSG ルールで通信が許可されているか確認
3. ルートテーブルの設定を確認
