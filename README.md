# Egg Atlas — GitHub modules

รองรับเฉพาะ PlaceID `107778070777162` หากอยู่แมพอื่น Loader, Main และชุดสำรอง จะหยุดทันทีโดยไม่เปิด UI หรือเริ่มฟีเจอร์

## ใช้งาน Public: SitXz120/Steel

Loader ในชุดนี้ตั้งค่าให้แล้ว: `Private=false`, Owner=`SitXz120`, Repo=`Steel`, Ref=`main`, Folder=`""` **ไม่ต้องสร้าง Token และไม่ต้องใช้ไฟล์ .token**

คัดลอกโค้ด `Loader.luau` ทั้งไฟล์ไปรันได้เลย ตัวโหลดจะดาวน์โหลด `UI.luau` และ `Main.luau` จาก repository นี้

หากต้องการเรียกด้วยคำสั่งบรรทัดเดียว ให้อัปโหลด **Loader.luau ที่ตั้งค่าแล้วจากชุดนี้** ไปไว้ที่หน้าแรกของ repository ด้วย แล้วจึงใช้:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/SitXz120/Steel/refs/heads/main/Loader.luau"))()
```

ขั้นตอน Token ด้านล่างใช้เฉพาะเมื่อเปลี่ยนกลับเป็น Private เท่านั้น

## ใช้กับ GitHub แบบ Private — ทำครั้งแรก

1. สร้าง repository แบบ **Private** แล้วอัปโหลด `Main.luau` และ `UI.luau` ไว้ที่หน้าแรกของ repository
2. เปิด [หน้าสร้าง Fine-grained token](https://github.com/settings/personal-access-tokens/new) ตั้งวันหมดอายุ เลือก **Only select repositories** แล้วเลือก repository นี้ ตั้ง Repository permissions เป็น **Contents: Read-only** แล้วสร้าง token หากเป็น repository ขององค์กร อาจต้องรอองค์กรอนุมัติสิทธิ์ด้วย
3. รันคำสั่งนี้ในช่องรันสคริปต์ที่ใช้อยู่ **ครั้งเดียว** โดยแทนข้อความในวงเล็บด้วย Token จริงของคุณ:

```lua
writefile("EggAtlas-GitHub.token", [[วาง_TOKEN_จริงของคุณตรงนี้]])
```

คำสั่งนี้บันทึก Token ในไฟล์ชื่อ `EggAtlas-GitHub.token` ภายใน workspace ที่ระบบรันสคริปต์ใช้ จึงไม่ต้องหาโฟลเดอร์ด้วยตัวเอง ไม่ต้องส่ง Token ในแชต และอย่าอัปโหลดไฟล์ `.token` หรือคำสั่งที่ใส่ Token จริงแล้วขึ้น GitHub หาก Token หมดอายุหรือเปลี่ยนใหม่ ให้รันคำสั่งเดิมด้วย Token ใหม่

4. เปิด `Loader.luau` ที่ให้มา แล้วแก้ค่า `Owner` กับ `Repo` ด้านบน:

```lua
local GITHUB={
    Private=true,
    Owner="ชื่อผู้ใช้หรือองค์กรบน_GitHub",
    Repo="ชื่อ_repository",
    Ref="main",
    Folder="",
    TokenFile="EggAtlas-GitHub.token",
}
```

ตัวอย่าง URL `https://github.com/example/EggAtlas` หมายถึง Owner=`example`, Repo=`EggAtlas` หากเก็บไฟล์ไว้หน้าแรก ใช้ Folder=`""` หากเก็บในโฟลเดอร์ `scripts/EggAtlas` ให้ใช้ Folder=`"scripts/EggAtlas"` และตั้ง Ref ให้ตรง branch ที่อัปโหลด

5. คัดลอกโค้ด **Loader.luau ทั้งไฟล์** ที่ตั้งค่าแล้ว ไปรันในช่องรันสคริปต์เดิม ต่อจากนั้นใช้ Loader ตัวนี้ซ้ำได้เลย ไม่ต้องสร้าง Token ใหม่ทุกครั้ง

**Loader ต้องเริ่มจากไฟล์ในเครื่อง** เพราะ Raw URL ของ Loader ที่อยู่ใน Private repository ต้องยืนยันสิทธิ์ตั้งแต่ก่อนโหลดเช่นกัน อย่าใช้ `loadstring(game:HttpGet(privateRawURL))()` เพื่อเริ่ม ตัว Loader ที่ให้มาจะอ่าน Token ในเครื่องและโหลด UI + Main ผ่าน GitHub API เอง

## หากใช้ Public repository

ตั้ง `Private=false` พร้อม Owner, Repo, Ref และ Folder ตามเดิม Loader จะโหลด Raw URL โดยไม่อ่านหรือส่ง Token สามารถรัน Loader ในเครื่อง หรืออัป Loader ที่ตั้งค่าแล้วไว้ Public และเรียก Raw URL ของ Loader ด้วย `loadstring(game:HttpGet(...))()` ได้

## แต่ละไฟล์ทำอะไร

| ไฟล์ | หน้าที่ |
| --- | --- |
| `UI.luau` | สี, layout, drag, ปุ่ม, แท็บ, การแสดงผลรายการไข่, Stats, Index และ Overview |
| `Main.luau` | อ่านข้อมูลเกม, เก็บไข่, The Rift, DR Scramble, ลำดับงาน, เส้นทาง และบันทึก config |
| `Loader.luau` | อ่าน Token จากเครื่องเมื่อใช้ Private โหลดและตรวจไฟล์ จากนั้นส่ง UI module ให้ Main |

โหลด UI module อย่างเดียวจะยังไม่สร้างหน้าต่างหรือเริ่ม automation โดย Main ส่งข้อมูลและ callback ให้ UI ผ่าน arguments; ไม่ใช้ตัวแปรร่วมใน `getgenv()` สำหรับเชื่อมสองโมดูล

Main ต้องรับ UI module จึงควรเรียกผ่าน Loader ไม่ใช่รัน Main เปล่า ๆ ทั้งสามไฟล์ต้องเป็นชุดเวอร์ชันเดียวกัน หากต้องการตรึงเวอร์ชัน ให้ใช้ commit SHA ใน `Ref` แทนชื่อ branch

## สิ่งที่ยังใช้เหมือนเดิม

- Config แยกตาม PlaceId และ UserId โดยใช้ชื่อไฟล์เดิม
- Left Alt ซ่อน/แสดง UI และลากหัวหน้าต่างได้
- รันซ้ำแล้วแทน UI เดิม พร้อมปิด connection และ controller ของชุดเก่า
- เมื่อ runtime รองรับการบันทึกไฟล์ ตัวโหลดจะเก็บ UI + Main ที่ดาวน์โหลดสำเร็จไว้เป็นชุดสำรองในเครื่อง; เวอร์ชันนี้ถอด Auto Boss และ Server Hop ออกแล้ว
- หากดาวน์โหลดหรือ compile ไม่สำเร็จ จะรายงานว่าเกิดที่ไฟล์/ขั้นตอนไหน ก่อนเริ่ม Main หากบันทึก resume ไม่ได้จะแจ้งเตือน และยังเปิดโปรแกรมได้
- Token ถูกใช้เฉพาะ Authorization header ของ GitHub API ไม่อยู่ใน URL, config เกม หรือไฟล์ resume ตัว Loader ไม่แสดง Token หรือ response body ในข้อความ HTTP ผิดพลาด
- HTTP 401: ตรวจ Token หมดอายุ/ถูกยกเลิก; 403: ตรวจสิทธิ์หรือ rate limit; 404: ตรวจ repository, branch, folder และสิทธิ์ Token; 429: รอสักครู่แล้วลองใหม่

การแยกไฟล์ช่วยให้แก้ไขและดูแลโค้ดสะดวกขึ้น ไม่ได้ลดงานที่ต้องทำในแต่ละเฟรมโดยตัวมันเอง Private mode ต้องมี `request` หรือ `http_request` และ `readfile` ใน runtime เดิมที่รันสคริปต์นี้ได้ การดาวน์โหลดผ่าน API และสิทธิ์ Contents: Read-only อ้างอิง [GitHub Docs](https://docs.github.com/en/rest/repos/contents#get-repository-content)

## นโยบายหลบสกิล

- กากบาทหมุน: กระโดด
- วงกลมขยาย: กระโดด
- บอลวิ่งตาม: เดินออกให้พ้นระยะ แล้วกลับเข้าตี
- อุกกาบาต: ยังไม่เชื่อมตัวตรวจวงเตือน เนื่องจากยังไม่พบวัตถุเตือนจริงขณะตรวจ ห้ามถือว่าเวอร์ชันนี้รองรับการหลบอุกกาบาตแล้ว

การแก้ Loader ในชุดนี้เป็นไฟล์ในเครื่อง ยังไม่ได้อัปโหลดหรือแก้ไฟล์บน GitHub แทนคุณ และยังไม่ได้แทนสคริปต์ที่กำลังรันในเกม

## เวอร์ชัน 11.31.0

- DR Scramble แทน Auto Boss: รอรอบตามเซิร์ฟเวอร์ ส่งไข่ที่ถือก่อน ติดตามหุ่นของบัญชีเรา ให้เกมตีตามคูลดาวน์ เก็บของ แล้วกลับจุดปลอดภัยและคืนงานให้ฟีเจอร์เดิม
- เลือกลำดับความสำคัญได้ใน Overview; Toggle กิจกรรมใหม่เริ่มปิด และบันทึกแยกจาก Auto Boss เดิม
- The Rift เลือก Any / Riftborn / Riftbeasts / Shattered Rift ได้ เกมเป็นผู้หมุนตู้: ตัวเลือกนี้รอให้ตู้ที่เลือกเปิดก่อนเก็บวัตถุดิบและผสม ไม่ได้บังคับเปลี่ยนตู้เซิร์ฟเวอร์ ระหว่างรอทำงานอื่นหรือวิ่งลู่วิ่ง
- Optimize Areas แสดงไข่ที่คู่แข่งถืออยู่ พร้อมชื่อผู้ถือและ CHASE; ติดตามไข่ใบเดิม ตีด้วยระบบไม้ของเกม เก็บเมื่อหลุด และกลับ Safezone ยกเลิกการไล่เมื่อผู้ถือเข้าจุดปลอดภัย
- กิจกรรมไม่ซื้อของ ไม่แลก Samples และไม่ทำเควสต์ Vault อัตโนมัติ
