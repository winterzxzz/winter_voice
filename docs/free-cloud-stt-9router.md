# Free fast cloud transcription with 9router

*[Tiếng Việt bên dưới ↓](#nhận-dạng-cloud-miễn-phí-với-9router)*

WinterVoice's **Local mode** is already free and 100% offline. If you want **faster transcription** without paying either, route WinterVoice through [9router](https://9router.com) — a local OpenAI-compatible API router — to a provider with a free speech-to-text tier such as **Groq's `whisper-large-v3-turbo`**.

Audio leaves your Mac in this mode (it goes to the provider you pick). Stay on Local mode if that matters to you.

## What you need

- 9router installed and running (its API listens on `http://localhost:20128/v1`)
- A free API key from a provider with an STT free tier (e.g. [Groq](https://console.groq.com) — generous free limits for `whisper-large-v3-turbo`)

## Set up 9router

1. Open the 9router dashboard: `http://localhost:20128/dashboard`
2. Go to **Media Providers → STT** (`/dashboard/media-providers/stt`)
3. Add your provider (e.g. **Groq**) and paste its API key
4. Note the model id 9router exposes, e.g. `groq/whisper-large-v3-turbo`

## Point WinterVoice at it

1. WinterVoice → **Settings → Transcription** → switch to **Remote**
2. Fill in:
   - **Base URL:** `http://localhost:20128/v1`
   - **Model:** `groq/whisper-large-v3-turbo`
   - **API key:** your 9router key if you configured one, otherwise leave empty
   - **Language:** pick your language or leave **Auto**
3. Press **Test Connection**, then **Save Configuration**

> WinterVoice normally requires HTTPS, but plain HTTP is explicitly allowed for `localhost` — a local router is exactly the case this exception exists for.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Connection refused | 9router isn't running — start it and reload the dashboard |
| 401 / authentication failed | Wrong or missing key — check the API key in Transcription settings |
| Model not found | The model id must match what 9router lists under Media Providers → STT |
| Slow or rate-limited | Free tiers have limits; switch the STT provider in 9router or fall back to Local mode |

---

# Nhận dạng cloud miễn phí với 9router

Chế độ **Local** của WinterVoice vốn đã miễn phí và chạy 100% offline. Nếu muốn **nhận dạng nhanh hơn** mà vẫn không tốn tiền, hãy cho WinterVoice đi qua [9router](https://9router.com) — một router API chuẩn OpenAI chạy ngay trên máy — tới nhà cung cấp có gói STT miễn phí, ví dụ **Groq `whisper-large-v3-turbo`**.

Ở chế độ này âm thanh sẽ rời khỏi máy (đi tới nhà cung cấp bạn chọn). Nếu điều đó quan trọng với bạn, cứ dùng Local.

## Cần chuẩn bị

- 9router đã cài và đang chạy (API nghe ở `http://localhost:20128/v1`)
- API key miễn phí của một nhà cung cấp có gói STT free (ví dụ [Groq](https://console.groq.com) — hạn mức free khá rộng cho `whisper-large-v3-turbo`)

## Cấu hình 9router

1. Mở dashboard: `http://localhost:20128/dashboard`
2. Vào **Media Providers → STT** (`/dashboard/media-providers/stt`)
3. Thêm nhà cung cấp (ví dụ **Groq**) và dán API key của họ
4. Ghi lại model id mà 9router expose, ví dụ `groq/whisper-large-v3-turbo`

## Trỏ WinterVoice vào 9router

1. WinterVoice → **Settings → Transcription** → chuyển sang **Remote**
2. Điền:
   - **Base URL:** `http://localhost:20128/v1`
   - **Model:** `groq/whisper-large-v3-turbo`
   - **API key:** key của 9router nếu bạn có đặt, không thì để trống
   - **Language:** chọn tiếng Việt hoặc để **Auto**
3. Bấm **Test Connection**, rồi **Save Configuration**

> WinterVoice bình thường bắt buộc HTTPS, nhưng HTTP thuần được phép riêng cho `localhost` — router chạy local chính là trường hợp ngoại lệ này sinh ra để phục vụ.

## Lỗi thường gặp

| Triệu chứng | Cách xử lý |
|---|---|
| Connection refused | 9router chưa chạy — bật lên rồi thử lại |
| 401 / lỗi xác thực | Key sai hoặc thiếu — kiểm tra API key trong Transcription settings |
| Không tìm thấy model | Model id phải khớp danh sách trong Media Providers → STT của 9router |
| Chậm / bị giới hạn | Gói free có hạn mức; đổi nhà cung cấp STT trong 9router hoặc quay về Local |
