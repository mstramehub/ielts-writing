# Lớp IELTS Writing | IELTS SPEEDING-UP

Web nộp bài IELTS Writing của **Ms Trâm English Hub**.
Học sinh nộp bài, giáo viên chấm (trên web hoặc tải về rồi gửi lại PDF), cả lớp xem được bài và nhận xét của nhau.

Hotline/Zalo: 079 29 51 529 · 0898 123 696 — 12 Lê Đình Chinh, Quy Nhơn Nam

---

## Cài đặt (làm một lần, khoảng 10 phút)

### 1. Tạo kho dữ liệu Supabase (miễn phí)
1. Vào https://supabase.com, đăng nhập và bấm **New project**. Đặt tên tuỳ ý, chọn vùng **Southeast Asia (Singapore)**.
2. Khi project tạo xong, mở **SQL Editor → New query**. Dán toàn bộ nội dung file `supabase/schema.sql` vào rồi bấm **Run**.
3. Mở **Authentication → Sign In / Providers → Email**:
   - Nếu không muốn học sinh phải bấm link xác nhận trong email, tắt **Confirm email**.
4. Mở **Authentication → URL Configuration**. Ở mục **Site URL**, điền link GitHub Pages của web, ví dụ `https://ten-tai-khoan.github.io/ten-repo/`.

### 2. Kết nối web với Supabase
1. Trong Supabase, mở **Project Settings → API** (hoặc **Data API**). Copy:
   - **Project URL**
   - Khoá **anon / publishable**
2. Mở file `config.js` trong repo này (trên GitHub bấm biểu tượng bút chì để sửa) và điền hai giá trị đó vào. Bấm **Commit changes**.

Khoá anon được phép để công khai. Dữ liệu đã được bảo vệ bằng quyền truy cập trong `schema.sql`.

### 3. Bật GitHub Pages
Vào **Settings → Pages** của repo. Ở mục **Source**, chọn **Deploy from a branch**, branch `main`, thư mục `/ (root)`, rồi bấm **Save**. Sau khoảng 1 phút web chạy ở `https://ten-tai-khoan.github.io/ten-repo/`.

### 4. Đặt tài khoản giáo viên
1. Mở web, chọn **Đăng ký** và tạo tài khoản bằng email của bạn.
2. Quay lại Supabase → **SQL Editor**, chạy câu lệnh sau (thay email của bạn vào):
   ```sql
   update public.profiles set role = 'teacher'
     where id = (select id from auth.users where email = 'EMAIL_CUA_BAN@gmail.com');
   ```
3. Tải lại web. Bên cạnh tên bạn sẽ hiện chữ **Giáo viên**.

---

## Cách dùng

**Học sinh**
- Đăng ký bằng email và mật khẩu, rồi vào tab **Nộp bài**: chọn Task 1 hoặc Task 2, dán đề và bài viết.
- Bài chưa chấm thì có thể **Rút bài**.
- Ở tab **Bài của lớp**, xem được tất cả bài cùng điểm và nhận xét.

**Giáo viên**
- **Tải bài về (Word)**: có nút trong từng bài. Ở danh sách cũng có nút tải tất cả bài đang hiển thị thành một file, mỗi bài một trang. Lọc "Chờ chấm" trước để chỉ tải bài chưa chấm.
- **Tải lên PDF đã chấm**: chấm trên máy xong thì tải file PDF lên đúng bài đó. Học sinh mở xem được ngay.
- **Chấm điểm trên web** (tuỳ chọn): chấm 4 tiêu chí TA/TR, CC, LR, GRA. Overall được tự tính và làm tròn 0.5. Bạn ghi nhận xét chung và liệt kê lỗi; các lỗi được gạch dưới ngay trong bài.

Học sinh quên mật khẩu: vào Supabase → **Authentication → Users**, chọn tài khoản đó và bấm **Send password recovery** (hoặc xoá tài khoản để em đăng ký lại).

## Các file
| File | Nội dung |
|---|---|
| `index.html` | Toàn bộ giao diện web |
| `config.js` | Địa chỉ và khoá Supabase |
| `logo-mark.png` | Logo |
| `supabase/schema.sql` | Bảng dữ liệu, quyền truy cập, kho file PDF |
