# Znachok BMW — мобильная апка (Flutter)

Заливает картинки и GIF на круглый дисплей-логотип по **Bluetooth (BLE)**.
Один код собирается под **Android и iOS**. Конвертация (480×480, круглая маска,
RGB565, раскладка GIF в кадры) делается в апке — устройство просто показывает.

## 0. Что нужно
- Flutter SDK (`flutter --version`, канал stable). Если нет — https://docs.flutter.dev/get-started/install
- Android: Android Studio / SDK (для сборки APK).
- iOS: Mac + Xcode (для сборки на iPhone).

## 1. Сгенерировать платформенные папки
В этой папке (`app/`) уже лежат `pubspec.yaml` и `lib/`. Добавь каркас android/ios:
```bash
cd app
flutter create --project-name znachok_bmw --platforms=android,ios .
flutter pub get
```
(существующие `lib/` и `pubspec.yaml` не перезапишутся)

## 2. Android — разрешения Bluetooth
Открой `android/app/src/main/AndroidManifest.xml` и **внутри `<manifest>` перед `<application>`** добавь:
```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
<!-- для Android 11 и старше: -->
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30"/>
```
Если в `android/app/build.gradle` `minSdkVersion` меньше 21 — поставь `minSdkVersion 21`.

## 3. iOS — описания доступа
В `ios/Runner/Info.plist` добавь ключи:
```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Для передачи картинок на дисплей-логотип по Bluetooth</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>Для передачи картинок на дисплей-логотип по Bluetooth</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Выбор картинок для дисплея</string>
<key>NSCameraUsageDescription</key>
<string>Снимок для дисплея</string>
```

## 4. Собрать и поставить
Android APK:
```bash
flutter build apk --release
# готовый файл: build/app/outputs/flutter-apk/app-release.apk
```
Или сразу на подключённый телефон:
```bash
flutter run --release
```
iOS: открой `ios/Runner.xcworkspace` в Xcode, подпиши своей учёткой, запусти на устройстве.

## 5. Пользоваться
1. Включи Bluetooth. Запусти апку, дай разрешения.
2. **Подключиться** → апка найдёт `Znachok-BMW`.
3. **Галерея/Камера** → выбери фото, либо **Файл/GIF** → выбери GIF из файлов → апка обрежет в круг, сожмёт и зальёт
   (полоса прогресса; полноразмерный кадр по BLE ~30–90 сек).
4. Список снизу: ▶ показать, 🗑 удалить.

## Соответствие прошивке
UUID и протокол зашиты в `lib/ble.dart` и совпадают с `src/main.cpp`:
- сервис `a1b20000-…`, CTRL `a1b20001-…` (команды/ответы), DATA `a1b20002-…` (байты).
- команды: `BEGIN:<имя>:<размер>`, `END`, `SHOW:<имя>`, `DEL:<имя>`, `LIST`.
- формат `.jpg` — статичная картинка 480×480; `.anm` — GIF как набор до 12 lossless RGB565-кадров с предзагрузкой в PSRAM; `.mjpg` — старый JPEG-анимационный fallback.
