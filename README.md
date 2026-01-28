# WordPress (Docker Compose) 開発用スタック

`docker compose up` だけで **DB + WordPress + 初期インストール** まで完了する構成です（初回のみ数十秒かかります）。

## 使い方

1) 環境変数ファイルを用意

```bash
cp .env.example .env
```

必要なら `.env` のパスワードやポートを変更してください。

2) 起動

```bash
docker compose up -d
```

> WPを特定バージョンで検証したい場合は `.env` に `WP_IMAGE` / `WPCLI_IMAGE` を設定して固定できます。

3) アクセス

- WordPress: `http://localhost:8080/`
- 管理画面: `http://localhost:8080/wp-admin/`
- phpMyAdmin: `http://localhost:8081/`

### EC2 等（パブリックIPでアクセス）

デフォルトは `WP_HTTP_PORT=8080` なので、セキュリティグループで 80 だけ開けている場合はアクセスできません。

- そのまま使う: `http://<public-ip>:8080/`（SG で 8080 を許可）
- 80番で使う: `.env` の `WP_HTTP_PORT=80` と `WP_SITE_URL=http://<public-ip>/` に変更して再起動

管理者アカウントは `.env` の `WP_ADMIN_USER / WP_ADMIN_PASSWORD` です。

> `WP_SITE_URL` は WordPress の `home/siteurl`（DB）にも保存されます。
> すでにインストール済みの状態でURLを変更したい場合でも、この構成では起動時（`wpcli` 実行時）に `WP_SITE_URL` へ自動同期します。

## 開発用のマウント

- リポジトリは **まっさらな土台** として使い、WordPressのデータ（`wp_data`）はDockerボリュームで管理します。
- `wp-content/` は生成物として扱い、リポジトリでは管理しません。

## プラグイン追加時にFTPを聞かれる場合

この構成では、初期化用の `wpcli` が起動時に権限を自動調整し、WordPress側は `FS_METHOD=direct` で直接書き込みします。

また、WordPressコンテナ起動時に `wp-content/uploads` などのディレクトリ作成と権限調整を行うため、
メディアアップロードやプラグインアップロードで `wp-content/uploads/YYYY/MM` に移動できない問題を起こしにくくしています。

### 「ディレクトリを作成できませんでした: /var/www/html/wp-content/upgrade/...」が出る場合

WordPress本体データ（`wp_data` ボリューム）側の `wp-content/upgrade` が書き込み不可になっている状態です。
この構成では起動時に `wpcli` が自動修正します。念のため再起動するなら:

```bash
docker compose up -d --force-recreate wordpress wpcli
```

## リセット（データ初期化）

```bash
docker compose down -v
```

> `-v` を付けると DB と WordPress 本体データのボリュームも消えます。
