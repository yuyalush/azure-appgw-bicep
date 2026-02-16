# Azure Application Gateway デプロイガイド

## このリポジトリの成り立ち

このプロジェクトは以下の流れで作成されました:

1. **concept.md の作成**: まず、Azure Application Gateway と VNet 構成シナリオのアーキテクチャ設計・要件を `concept.md` に定義しました。このファイルがすべてのリソース構成・ネットワーク設計・セキュリティ要件の正（Source of Truth）となります。
2. **Agent によるファイル群の生成**: `concept.md` の内容を基に、AI Agent が Bicep テンプレート（`main.bicep`、各モジュール）、パラメータファイル（`main.bicepparam`）、cloud-init スクリプトなどのデプロイに必要なファイル群を自動生成しました。

設計変更が必要な場合は、まず `concept.md` を更新し、それに合わせてデプロイファイルを修正してください。

## 📁 ファイル構成

```
.
├── concept.md                      # アーキテクチャ設計ドキュメント (Source of Truth)
├── main.bicep                      # メインオーケストレーションファイル
├── main.bicepparam                 # パラメータファイル
├── README.md                       # このファイル
├── modules/
│   ├── network.bicep              # VNet、サブネット、NSG、ピアリング
│   ├── appgw.bicep                # Application Gateway
│   └── vm.bicep                   # Virtual Machine
└── cloud-init/
    ├── vm1-nginx.yaml             # Backend VM1 初期化スクリプト (nginx)
    └── vmtest-tools.yaml          # Test VM 初期化スクリプト (curl, jq 等)
```

## 🚀 デプロイ手順

### 1. Azure CLI のセットアップと認証

```bash
# Azure CLI にログイン
az login

# ターゲットとするサブスクリプションを設定
az account set --subscription "<サブスクリプションIDまたは名前>"

# 現在のサブスクリプションを確認
az account show --output table
```

### 2. SSH Key Pair の生成

```bash
# SSH キーペアを生成
ssh-keygen -t rsa -b 4096 -f ~/.ssh/vm-ssh-key -C "azureuser@azure-vms"

# 公開鍵の内容を確認
cat ~/.ssh/vm-ssh-key.pub

# (オプション) Azure Key Vault に秘密鍵を保存
az keyvault secret set \
  --vault-name <KeyVault名> \
  --name vm-ssh-private-key \
  --file ~/.ssh/vm-ssh-key
```

### 3. パラメータファイルへの SSH 鍵の設定（推奨）

SSH 鍵は `main.bicepparam` に直接記載することを推奨します。デプロイ時に `--parameters` で渡す方法ではなく、bicepparam ファイルに事前に設定してください。

`main.bicepparam` を開き、以下の SSH 鍵パラメータを設定します:

```bicep
// SSH 公開鍵を設定 (必須)
// ssh-keygen で生成した公開鍵 (~/.ssh/vm-ssh-key.pub) の内容を貼り付け
param sshPublicKey = 'ssh-rsa AAAA...(公開鍵の内容)... azureuser@azure-vms'

// SSH 秘密鍵を設定 (推奨)
// Test VM から VM1 への SSH 接続に使用する秘密鍵
// 設定すると Custom Script Extension により Test VM の
// /home/azureuser/.ssh/vm-ssh-key に自動配置されます
param sshPrivateKey = '-----BEGIN OPENSSH PRIVATE KEY-----\n...(秘密鍵の内容)...\n-----END OPENSSH PRIVATE KEY-----'
```

> **注意**: `sshPrivateKey` を設定すると、デプロイ時に Custom Script Extension が Test VM に秘密鍵を自動配置し、`connect-vm1.sh` スクリプトですぐに VM1 へ SSH 接続できます。空のままにした場合は、デプロイ後に SCP 等で手動転送が必要です。

### 4. リソースグループの作成

```bash
az group create \
  --name rg-appgw-demo \
  --location japaneast
```

### 5. Bicep のデプロイ

```bash
# パラメータファイルを使用してデプロイ
az deployment group create \
  --resource-group rg-appgw-demo \
  --template-file main.bicep \
  --parameters main.bicepparam
```

### 6. デプロイ結果の確認

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

### 1. インターネットからのアクセステスト

デプロイ後、Application Gateway の Public IP にブラウザまたは curl でアクセスし、VM1 の Web サーバーが正常に応答することを確認します。

```bash
curl http://<AppGW-Public-IP>
```

Azure Portal で Application Gateway の Backend Health を確認し、VM1 が Healthy であることも検証してください。

### 2. JIT を使用して Test VM に接続

JIT (Just-In-Time) VM Access の設定は Azure Portal から行います。CLI での JIT 設定は制約があるため、以下の Portal 手順に従ってください。

#### Step 1: Microsoft Defender for Cloud を有効化

1. [Azure Portal](https://portal.azure.com) にサインイン
2. 検索バーで「**Microsoft Defender for Cloud**」を検索して選択
3. 左側メニューから「**環境設定**」を選択
4. 対象のサブスクリプションをクリック
5. 「**Defender プラン**」で「**サーバー**」を「**オン**」に設定（無料試用版または有料版）
6. 「**保存**」をクリック

#### Step 2: VM-Test で JIT アクセスを有効化

1. Azure Portal で「**仮想マシン**」を検索して選択
2. 対象の VM「**vm-test**」をクリック
3. 左側メニューから「**構成**」→「**Just-In-Time VM アクセス**」を選択
   - または Microsoft Defender for Cloud →「**ワークロード保護**」→「**Just-In-Time VM アクセス**」からアクセス
4. 「**JIT VM アクセスを有効にする**」をクリック
5. JIT ポリシーを設定:
   - **ポート 22 (SSH)**:
     - 最大リクエスト時間: **3 時間**
     - 許可される送信元 IP: **マイ IP** または特定の IP 範囲を指定
6. 「**保存**」をクリック

#### Step 3: JIT アクセスをリクエスト

1. VM「**vm-test**」の画面で「**接続**」をクリック
2. 「**マイ IP**」タブを選択（または「Just-In-Time」タブ）
3. 「**アクセス権の要求**」をクリック
4. リクエストの詳細を設定:
   - **ポート**: 22 (SSH)
   - **送信元 IP**: マイ IP（自動検出）または手動で IP を入力
   - **時間範囲**: 3 時間（またはカスタム設定）
5. 「**ポートを開く**」をクリック
6. ステータスが「**承認済み**」になるまで待機（通常は数秒）

#### Step 4: SSH 接続

許可された時間内にローカル端末から Test VM に SSH 接続:

```bash
ssh -i ~/.ssh/vm-ssh-key azureuser@<Test-VM-Public-IP>
```

> **注意事項**:
> - JIT アクセスは指定した時間が経過すると自動的に無効化されます
> - 再度接続が必要な場合は、Step 3 からアクセス要求を再実行してください
> - Azure Portal の「アクティビティ ログ」でアクセス履歴を確認できます

### 3. Test VM から Application Gateway への curl テスト

Test VM にログイン後、AppGW の Public IP に HTTP リクエストを送信:

```bash
# AppGW の Public IP を確認
APPGW_IP="<AppGW-Public-IP>"

# 基本的な curl テスト
curl -v http://$APPGW_IP

# 複数回リクエストして応答を確認
for i in {1..10}; do
  echo "Request $i:"
  curl -s http://$APPGW_IP | grep -o "<h1>.*</h1>"
  sleep 1
done

# ヘッダー情報も含めて確認
curl -I http://$APPGW_IP
```

### 4. Test VM から Backend VM1 への SSH 接続

Test VM から VNet ピアリング経由で VM1 に SSH 接続します。`sshPrivateKey` パラメータを設定してデプロイした場合、秘密鍵は Custom Script Extension により `/home/azureuser/.ssh/vm-ssh-key` に自動配置されています。

```bash
# Test VM にログイン後、付属のスクリプトで VM1 に接続
./connect-vm1.sh

# または直接接続
ssh -i ~/.ssh/vm-ssh-key azureuser@10.1.1.4

# VM1 で nginx の状態を確認
sudo systemctl status nginx
sudo tail -f /var/log/nginx/access.log
```

> **秘密鍵が配置されていない場合**: `sshPrivateKey` パラメータを空のままデプロイした場合は、ローカルから手動で転送してください:
> ```bash
> scp -i ~/.ssh/vm-ssh-key ~/.ssh/vm-ssh-key azureuser@<Test-VM-Public-IP>:~/.ssh/vm-ssh-key
> ssh -i ~/.ssh/vm-ssh-key azureuser@<Test-VM-Public-IP> "chmod 600 ~/.ssh/vm-ssh-key"
> ```

### 5. VNet 構成・Backend Pool の確認

1. Azure Portal で Application Gateway の Backend Pool を確認し、VM1 (VNet2) のみが含まれていることを検証
2. VNet 構成が以下の通りであることを確認:
   - VNet1 (`vnet-appgw`): Application Gateway サブネットのみ
   - VNet2 (`vnet-backend`): VM1 が配置
   - VNet3 (`vnet-test`): Test VM が配置
3. VNet Peering が正しく構成されていることを確認 (VNet1↔VNet2、VNet2↔VNet3)

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
- **必要なサービス**: Microsoft Defender for Cloud（サーバープランを有効化）
- **ポート**: SSH (22)
- **最大接続時間**: 3 時間
- **設定方法**: Azure Portal から設定（詳細は「検証手順」の JIT セクションを参照）
- **アクセスフロー**:
  1. Azure Portal で JIT アクセスをリクエスト
  2. 指定した時間内に限り、指定 IP から SSH 接続が可能
  3. 時間経過後、NSG ルールが自動的に削除される

### NSG ルール

- **AppGW サブネット**: HTTP (80), HTTPS (443), GatewayManager (65200-65535) を許可
- **VM1 サブネット**: AppGW サブネット (`10.0.1.0/24`) からの HTTP (80)、Test VM サブネット (`10.2.1.0/24`) からの SSH (22) を許可
- **Test VM サブネット**: JIT により動的に管理（静的な SSH ルールは不要）

### SSH 鍵の管理

- **公開鍵**: `main.bicepparam` に記載し、Bicep の `linuxConfiguration` で両 VM の `authorized_keys` に自動配置
- **秘密鍵**: `main.bicepparam` に記載を推奨。設定すると Custom Script Extension により Test VM の `/home/azureuser/.ssh/vm-ssh-key` に自動配置（パーミッション 600）
- **秘密鍵の保管**: ローカルに安全に保管するほか、Azure Key Vault への保存も推奨

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
- VM (Standard_B2ps_v2) x 2: ~$30-40/月 x 2
- Public IP (Standard) x 2: ~$3/月 x 2
- VNet Peering: データ転送量に応じて
- Managed Disks (Premium_LRS 30GB): ~$5/月 x 2

**合計概算**: ~$280-400/月

## 📚 参考資料

- [Application Gateway ドキュメント](https://learn.microsoft.com/azure/application-gateway/)
- [VNet Peering ドキュメント](https://learn.microsoft.com/azure/virtual-network/virtual-network-peering-overview)
- [JIT VM Access ドキュメント](https://learn.microsoft.com/azure/defender-for-cloud/just-in-time-access-usage)
- [Bicep ドキュメント](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
- [Microsoft Defender for Cloud](https://learn.microsoft.com/azure/defender-for-cloud/)

## 🐛 トラブルシューティング

### Backend Health が Unhealthy の場合

1. VM1 で nginx が起動しているか確認:
   ```bash
   ssh -i ~/.ssh/vm-ssh-key azureuser@10.1.1.4
   sudo systemctl status nginx
   ```
2. NSG ルールで AppGW サブネット (`10.0.1.0/24`) からの通信が許可されているか確認
3. Application Gateway のヘルスプローブ設定を確認

### Test VM に SSH 接続できない場合

1. JIT アクセスが Azure Portal で有効化されているか確認
2. JIT アクセスリクエストが承認済みか確認（ステータスが「承認済み」であること）
3. 接続元 IP が JIT ポリシーで許可されているか確認
4. Test VM に Public IP が割り当てられているか確認

### VNet ピアリングが動作しない場合

1. ピアリングのステータスが "Connected" になっているか確認
2. NSG ルールで通信が許可されているか確認
3. ルートテーブルの設定を確認
