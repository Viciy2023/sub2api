#!/bin/bash
# Supabase Storage sync script for auth files
# Bucket: clipro, Path: auths/

BUCKET="clipro"
AUTH_DIR="/app/auths"
SUPABASE_API="${SUPABASE_URL}/storage/v1"

# Upload a single file to Supabase Storage
upload_file() {
  local filepath="$1"
  local filename=$(basename "$filepath")

  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "${SUPABASE_API}/object/${BUCKET}/auths/${filename}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}" \
    -H "Content-Type: application/json" \
    -H "x-upsert: true" \
    --data-binary @"${filepath}")

  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
    echo "[SYNC] Uploaded ${filename} to Supabase (${HTTP_CODE})"
  else
    echo "[SYNC] Failed to upload ${filename} (HTTP ${HTTP_CODE})"
  fi
}

# Upload all files in auth dir
upload_all() {
  echo "[SYNC] Uploading all auth files to Supabase..."
  for f in "${AUTH_DIR}"/*.json; do
    [ -f "$f" ] && upload_file "$f"
  done
}

# Download all auth files from Supabase
download() {
  echo "[SYNC] Listing files in Supabase bucket..."

  local offset=0
  local limit=1000
  local total_downloaded=0
  local batch_count=0

  while true; do
    batch_count=$((batch_count + 1))
    echo "[SYNC] Fetching batch ${batch_count} (offset: ${offset}, limit: ${limit})..."
    
    FILE_LIST=$(curl -s \
      -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}" \
      -H "Content-Type: application/json" \
      "${SUPABASE_API}/object/list/${BUCKET}" \
      -d "{\"prefix\":\"auths/\",\"limit\":${limit},\"offset\":${offset}}")

    if echo "$FILE_LIST" | jq -e '.[0].name' > /dev/null 2>&1; then
      FILE_COUNT=$(echo "$FILE_LIST" | jq length)
      echo "[SYNC] Found ${FILE_COUNT} files in this batch"

      # Download each file in the batch
      local downloaded_in_batch=0
      while IFS= read -r filename; do
        if [ -n "$filename" ] && [ "$filename" != "null" ] && [ "$filename" != ".emptyFolderPlaceholder" ]; then
          echo "[SYNC] Downloading ${filename}..."
          if curl -s \
            -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}" \
            "${SUPABASE_API}/object/${BUCKET}/auths/${filename}" \
            -o "${AUTH_DIR}/${filename}"; then
            echo "[SYNC] Saved ${AUTH_DIR}/${filename}"
            downloaded_in_batch=$((downloaded_in_batch + 1))
          else
            echo "[SYNC] Failed to download ${filename}"
          fi
        fi
      done < <(echo "$FILE_LIST" | jq -r '.[].name')

      total_downloaded=$((total_downloaded + downloaded_in_batch))
      echo "[SYNC] Batch ${batch_count} complete: ${downloaded_in_batch} files downloaded"

      # If we got fewer files than the limit, we've reached the end
      if [ "$FILE_COUNT" -lt "$limit" ]; then
        echo "[SYNC] All batches complete. Total files downloaded: ${total_downloaded}"
        break
      fi

      offset=$((offset + limit))
    else
      if [ "$offset" -eq 0 ]; then
        echo "[SYNC] No files found in Supabase or API error"
        echo "[SYNC] Response: ${FILE_LIST}"
      else
        echo "[SYNC] All batches complete. Total files downloaded: ${total_downloaded}"
      fi
      break
    fi
  done
}

# Watch auth directory for changes and sync to Supabase
watch_dir() {
  echo "[SYNC] Starting file watcher on ${AUTH_DIR}..."
  inotifywait -m -r -e close_write,create,modify,delete "${AUTH_DIR}" --format '%e %f' | while read event filename; do
    if [[ "$filename" == *.json ]]; then
      echo "[SYNC] Detected event: ${event} on ${filename}"
      sleep 2
      
      if [[ "$event" == "DELETE" ]]; then
        # File was deleted, remove from Supabase
        echo "[SYNC] Deleting ${filename} from Supabase..."
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
          -X DELETE "${SUPABASE_API}/object/${BUCKET}/auths/${filename}" \
          -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}")
        
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "204" ]; then
          echo "[SYNC] Deleted ${filename} from Supabase (${HTTP_CODE})"
        else
          echo "[SYNC] Failed to delete ${filename} from Supabase (HTTP ${HTTP_CODE})"
        fi
      else
        # File was created or modified, upload to Supabase
        if [ -f "${AUTH_DIR}/${filename}" ]; then
          upload_file "${AUTH_DIR}/${filename}"
        fi
      fi
    fi
  done
}

case "$1" in
  download) download ;;
  upload) upload_file "$2" ;;
  upload-all) upload_all ;;
  watch) watch_dir ;;
  *) echo "Usage: $0 {download|upload <file>|upload-all|watch}"; exit 1 ;;
esac
