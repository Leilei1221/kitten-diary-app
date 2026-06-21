# 奶貓日記 App

奶貓照護紀錄 App，可記錄一梯奶貓、每隻奶貓資料、餵奶排泄、體重、醫療、奶粉、交班與相簿連結。

## 手機使用

這個專案可用 GitHub Pages 上架。網站檔案放在：

```text
docs/index.html
```

上架後，手機直接開 GitHub Pages 網址即可使用。

## GitHub Pages 設定

推到 GitHub 後，到 repository：

```text
Settings → Pages
```

設定：

```text
Source: Deploy from a branch
Branch: main
Folder: /docs
```

儲存後等待幾分鐘，GitHub 會產生公開網址。

## Supabase 設定

App 內右上角「共用登入」需要填：

- Supabase Project URL
- Supabase anon public key
- Email
- 密碼
- 照護空間代碼
- 照顧者名稱

不要把 service role key 放進前端或 GitHub。

## Supabase Auth 網址設定

若要在手機與 GitHub Pages 正常使用登入，請到 Supabase：

```text
Authentication → URL Configuration
```

加入 GitHub Pages 網址到允許清單，例如：

```text
https://你的帳號.github.io/你的repo名稱/
```

## 資料庫

Supabase migration 放在：

```text
supabase/migrations/
```

已包含奶貓日記後台資料庫、RLS 權限與照片 bucket 設計。
