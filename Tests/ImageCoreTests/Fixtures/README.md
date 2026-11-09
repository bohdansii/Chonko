# Synthetic HDR fixture

`hdr-gainmap.jpg` is a generated 64×64 constant-color image, not a photograph. It was created with Apple's CoreImage on macOS 27.2 using an SDR CIImage and a two-stop brighter HDR CIImage with contentHeadroom 4. The JPEG is 8-bit, has one primary ImageIO image, and includes an ISO HDR gain map.

Reproduction (Swift, macOS 26+):

```swift
import CoreImage
let sdr = CIImage(color: CIColor(red: 0.5, green: 0.25, blue: 0.1))
    .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
let hdr = sdr.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 2.0])
    .settingContentHeadroom(4.0)
try CIContext().writeJPEGRepresentation(of: sdr, to: outputURL,
    colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, options: [.hdrImage: hdr])
```

This fixture is committed so testing does not require GPU access or CoreImage rendering inside a sandbox.
