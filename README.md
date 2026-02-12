# L*a*b* Bean Color Analysis Mobile Application

This folder contains a **Flutter-based mobile application** developed as part of the undergraduate thesis project **"Bean Color Quality Prediction Using Deep Learning"**.

The application allows users to capture or select images of bean grains and automatically predict their **L\*, a\*, and b\*** color parameters using deep learning models executed locally on the device.

---

## Application Overview

The app integrates **TensorFlow Lite models** generated from the machine learning pipeline and performs **offline inference**, meaning no internet connection is required.

### Main Features
- Capture images using the device camera  
- Select images from the device gallery  
- On-device inference using TensorFlow Lite  
- Prediction of L\*, a\*, and b\* color parameters  
- Persistent local storage of analyzed samples  
- Fully offline operation  

---

## Machine Learning Models

The application uses three TensorFlow Lite models located in `assets/models/`:

| Model            | Predicted Parameter | Description       |
|-----------------|---------------------|-------------------|
| `modelL.tflite` | L\*                 | Lightness         |
| `modela.tflite` | a\*                 | Green–Red axis    |
| `modelb.tflite` | b\*                 | Blue–Yellow axis  |

### Model Input Specifications
- Image size: **224 × 224 pixels**  
- Color format: RGB  
- Normalization: pixel values scaled to `[0.0, 1.0]`  
- Input tensor shape: `[1, 224, 224, 3]`  

---

## Technologies Used

- **Flutter**  
- **Dart**  
- **TensorFlow Lite**  
- `tflite_flutter`  
- `image_picker`  
- `shared_preferences`  
- `image`  

---

## Installation and Execution

### Prerequisites
- Flutter SDK installed  
- Android SDK configured  
- Android device or emulator  

### Run the Application

```bash
flutter pub get
flutter run
```

**Build (Android APK)**

```bash
flutter clean
flutter pub get
flutter build apk --release
```

The generated APK will be available at:

`build/app/outputs/flutter-apk/app-release.apk`

---

## Image Preprocessing Pipeline

Before inference, the selected image goes through the following steps:

- Image loading  
- Decoding  
- Resizing to 224 × 224  
- RGB channel extraction  
- Pixel normalization  
- Tensor creation for model input  

---

## Data Persistence

Uses `SharedPreferences` for local storage.

Stores:

- Image file path  
- Predicted L\*, a\*, b\* values  

Stored data remains available after app restarts.

---

## Notes

- All inference is performed locally on the device.  
- No user data is transmitted or stored externally.  
- The app was designed as a proof of concept for agricultural quality analysis.  

---

## License

This application is part of an academic undergraduate thesis project (TCC).

---

## Author

Matheus Henrique Carvalho dos Santos de Souza