<p align="center"><img src="docs/icon.png" width="96" alt="Tab Mixer"></p>

<h1 align="center">Tab Mixer</h1>

<p align="center">Chrome'daki her videoyu ve Mac'teki her uygulamanın sesini menü çubuğundan yönet.</p>

---

macOS'un "Şu An Çalan" menüsü Chrome'da aynı anda açık olan videolardan sadece birini gösterir. Tab Mixer, Chrome'daki bütün video sekmelerini menü çubuğunda ayrı ayrı listeler ve her birini tek tıkla oynatıp durdurmanı, sesini ayrı ayrı ayarlamanı sağlar.

## Özellikler

- **Chrome video listesi:** Şu an çalanlar ve son 10 dakikada durdurulanlar, site ikonlarıyla birlikte. YouTube ana sayfasındaki gibi sessiz önizlemeler listeye girmez.
- **Oynat / durdur:** Videonun adına tıkla. İframe içindeki oynatıcılarla da çalışır.
- **Video başına ses:** Her videonun kendi ses çubuğu var.
- **Uygulama mikseri:** Chrome, Discord, WhatsApp gibi uygulamaların sesini ayrı ayrı kıs.
- **Mac sesi:** En üstte genel ses ve çıkış cihazı.
- **Sekmeye git:** Videonun sekmesini tek tıkla öne getir.
- Hiçbir veri bilgisayarından dışarı çıkmaz. İnternete bağlanmaz, analitik toplamaz.

## Gereksinimler

- macOS 14.4 veya üstü (Apple Silicon ve Intel)
- Google Chrome

## Kurulum

### 1. Uygulamayı kur

1. [Releases](../../releases/latest) sayfasından `TabMixer-x.y.z.zip` dosyasını indir ve aç.
2. `Tab Mixer.app` dosyasını **Uygulamalar** klasörüne sürükle.
3. Uygulamayı aç. Uygulama Apple'a kayıtlı bir geliştirici sertifikasıyla imzalanmadığı için macOS ilk açılışta uyarı verir:
   - **Sistem Ayarları › Gizlilik ve Güvenlik** bölümüne git, en altta **"Yine de Aç"** butonuna bas.
   - Ya da Terminal'de: `xattr -dr com.apple.quarantine "/Applications/Tab Mixer.app"`

Menü çubuğunda Tab Mixer ikonu görünür.

### 2. Chrome eklentisini yükle

Uygulama ilk açılışta bir **kurulum yardımcısı** gösterir:

1. **"Eklentiler sayfasını aç"** butonuna bas.
2. Chrome'da sağ üstteki **Geliştirici modu** anahtarını aç.
3. Yardımcıdaki **"Beni Chrome'a sürükle"** kutusunu Chrome'daki sayfanın üzerine sürükleyip bırak.

Eklenti bağlanınca yardımcı "Hazır!" der. Açık video sekmelerini bir kez yenile.

Yardımcıyı sonradan **Ayarlar… › Chrome eklentisi › Kurulum yardımcısını aç** ile tekrar açabilirsin. Sürükleme çalışmazsa **"klasör yolunu kopyala"** bağlantısına bas, Chrome'da **Paketlenmemiş öğe yükle**'ye bas, **⌘⇧G** ile yolu yapıştırıp klasörü seç.

> Chrome açılışta ara sıra "geliştirici modundaki eklentileri devre dışı bırak" diye hatırlatma gösterebilir. Bunu kapatman yeterli, eklenti çalışmaya devam eder.

## İzinler ve gizlilik

Tab Mixer **veri toplamaz.** Mikrofon, kamera, ekran kaydı veya dosyalarına erişim istemez. Kurulumda karşına çıkabilecek her şey şunlar:

| Ne | Ne zaman | Neden |
|---|---|---|
| "Tanınmayan geliştirici" uyarısı | İlk açılışta | Uygulama ücretli Apple sertifikasıyla imzalanmadı. Bir izin değil, bir kez "Yine de Aç" demen yeterli. |
| **Chrome eklentisi** izinleri | Eklenti kurulurken | Sayfalardaki video oynatıcılarını bulmak, sekme adını göstermek ve uygulamayla konuşmak için. Videolar çoğu zaman başka sitelerin içinde (iframe) oynadığı için Chrome bunu "tüm sitelerdeki verileri okuma" olarak gösterir. Eklenti sadece video ve ses öğelerine bakar. Sayfa içeriğini, şifreleri veya formları okumaz. |
| **Yalnızca Sistem Sesi Kaydı** *(isteğe bağlı)* | Bir uygulamanın sesini ilk kez %100'ün altına çektiğinde | macOS'ta bir uygulamanın sesini ayrı kısmanın tek yolu, sesini hoparlöre gitmeden önce alıp kısarak çalmak. Sadece Mac'ten çıkan sese erişir. Ses kaydedilmez, saklanmaz. Vermezsen sadece uygulama ses çubukları çalışmaz. |
| Giriş öğesi bildirimi *(isteğe bağlı)* | "Mac açılınca başlat"ı açınca | macOS'un standart bildirimi. |

Bütün izinlerin durumu ve açıklaması uygulamanın **Ayarlar › İzinler ve gizlilik** bölümünde de görünür.

> Uygulama imzasız olduğu için her yeni sürümden sonra macOS Sistem Sesi Kaydı iznini tekrar sorabilir.

## Güvenlik

- Uygulama dışarıdan bağlantı kabul etmez ve yönetici yetkisi istemez.
- Chrome köprüsü sadece Tab Mixer eklentisinin kimliğiyle konuşur (`allowed_origins`).
- Uygulama ile köprü arasındaki soket ve durum dosyası sadece senin kullanıcı hesabının erişebileceği bir klasördedir (`~/Library/Caches/tab-mixer`, izin `700`, soket `600`).
- Web sayfalarından gelen veriler tür ve aralık kontrolünden geçer. Köprüye gelen mesajların boyutu sınırlıdır.
- Her sürümün `SHA-256` özeti Releases sayfasında yazar. İndirdiğin dosyayı doğrulamak için: `shasum -a 256 TabMixer-x.y.z.zip`
- Bir güvenlik sorunu bulursan lütfen [Issues](../../issues) üzerinden bildir.

## Nasıl çalışır

```
Chrome sekmeleri ──(eklenti)──► native messaging ──► Tab Mixer.app ──► menü çubuğu
                                                         │
                         Core Audio process tap ◄────────┘  (uygulama sesleri)
```

- **Eklenti** (`Extension/`), sayfalardaki video ve ses öğelerini izler. Hangi videonun çaldığını, ne zaman durduğunu ve ses seviyesini uygulamaya bildirir.
- **Uygulama** (`Sources/TabMixer/`), Chrome tarafından köprü olarak da başlatılır. Eklentiden gelen durumu okur, menüden gelen komutları eklentiye iletir.
- **Uygulama sesleri** macOS'un Core Audio "process tap" özelliğiyle ayarlanır. Uygulamanın sesi hoparlöre gitmeden önce yakalanır ve kısılmış olarak çalınır.

Kulağına gelen ses üç ayarın çarpımıdır: **Mac sesi × uygulama sesi × video sesi.**

## Kaynaktan derleme

Xcode 16 veya üstü gerekir.

```bash
git clone https://github.com/omerfarukgzr/tab-mixer.git
cd tab-mixer
scripts/build.sh            # dist/Tab Mixer.app ve dist/TabMixer-x.y.z.zip
scripts/build.sh --install  # ayrıca ~/Applications'a kurar ve başlatır
```

## Kaldırma

1. Menüden **Çık**'a bas ve `Tab Mixer.app` dosyasını çöpe at.
2. Chrome'da `chrome://extensions` sayfasından eklentiyi kaldır.
3. İstersen şu dosyaları da sil:
   - `~/Library/Application Support/Tab Mixer`
   - `~/Library/Caches/tab-mixer`
   - `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/io.github.omerfarukgzr.tabmixer.json`

---

## English

**Tab Mixer** is a macOS menu bar app that lists every playing video in Chrome (not just one, like Now Playing does), lets you play/pause each one, set per-video volume, and mix per-app volume (Chrome, Discord, …) using Core Audio process taps.

**Install:** download the zip from [Releases](../../releases/latest), move `Tab Mixer.app` to Applications, and open it (the app is not notarized: use *System Settings › Privacy & Security › Open Anyway*). On first launch a setup assistant opens `chrome://extensions`; enable *Developer mode* and drag the extension tile from the assistant onto the page.

No data leaves your Mac. Requires macOS 14.4+ and Google Chrome. MIT licensed.
