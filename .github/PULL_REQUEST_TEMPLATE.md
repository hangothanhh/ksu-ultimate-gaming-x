## Mô tả thay đổi
- Thay đổi cái gì?
- Lý do cần thay đổi?

## Danh sách file bị sửa
- ...

## Kiểm thử đã thực hiện
- [ ] `python -u tests/verify_all.py` (hoặc `--skip-apk` trên Linux) PASS 100%
- [ ] `python -u scripts/build_zip.py` đóng gói sạch, không lỗi LF/CRLF
- [ ] Kiểm thử trên thiết bị thật (ghi rõ model, Android, KernelSU nếu có; nếu chỉ test mock hãy ghi rõ):

## Tác động tương thích & khả năng rollback
- Thay đổi có ảnh hưởng `global.conf`, `orig_*.env`, `system.prop` hoặc `zygisk/arm64-v8a.so` không?
- Khi bật `SAFE_MODE=1` hoặc gỡ module có hoàn nguyên sạch không?

## Minh bạch về AI & Chống "AI Slop" (Bắt buộc)
- [ ] Tôi xác nhận không dán code AI tạo hàng loạt ("AI slop") mà chưa đọc hiểu, chưa tự rà lỗi POSIX/nhớ/sysfs hoặc bịa đặt khả năng tương thích thiết bị.
- Mức độ hỗ trợ của AI trong PR này (nếu có):
  - [ ] Không dùng AI
  - [ ] Có dùng AI hỗ trợ — đã đọc lại toàn bộ diff và chạy test xác minh
- Những phần nào CHỈ mới chạy mock hoặc chưa test được trên máy thật?
