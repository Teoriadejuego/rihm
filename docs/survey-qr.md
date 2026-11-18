# Class survey QR

In the researcher panel, open **Survey QR**, then select **Generate QR**.
Project the QR with **Project QR**, or use **Download QR image** to save a PNG
for a slide. The image includes the label **Code** and the same six-digit code
under the QR. **Copy survey link** shares the identical invitation without scanning.

Every invitation uses the owner's survey:
`https://investigadoresloyola.eu.qualtrics.com/jfe/form/SV_cw4cVf23LI4rJzg`
with the query parameter `Treatment_choice` set to the generated code. A read-only
check of the survey flow confirmed that this exact embedded field takes its value
from the recipient/URL rather than a fixed value. No survey responses were submitted
and no questionnaire or flow was changed during this implementation.

Keep the same QR for everyone in a class. **Generate new QR** creates a different
code for a new group. The code survives switching panel tabs and entering/leaving
fullscreen. It is not saved across page reloads or sign-out: download the image
first if it will be needed again. A six-digit code is a convenient group label,
not a password or a globally unique identifier.

The QR is generated locally in the authenticated panel browser using secure random
numbers and a bundled encoder. Generation, copying, projection and downloading make
no requests to Qualtrics or a third-party QR service. A student scanning the QR opens
Qualtrics directly. Generated codes are not sent to GitHub or the public dashboard.
Students' subsequent survey submissions carry the shared code in Qualtrics.

Publication still selects the database-relative latest response hour. This feature
does not filter published results by the generated code or alter the privacy rules.

## Encoder provenance

The vendored `admin/www/qrcodegen-v1.8.0.js` is Project Nayuki's
[QR Code generator](https://www.nayuki.io/page/qr-code-generator-library), release
[v1.8.0 ES6](https://github.com/nayuki/QR-Code-generator/releases/download/v1.8.0/qrcodegen-v1.8.0-es6.js).
Its MIT license remains in the source header. The only local addition is an ES module
export. The original release file SHA-256 is
`6a1116192ed1dd67fa1bf31e77f5817103d71c23bbac24c382e698b7668bdd01`.
No CDN is used at runtime. QR rendering uses quartile error correction (or higher)
and a four-module white border.

## Verification

`npm test` checks code boundaries, random rejection sampling, regeneration, the exact
survey URL and parameter, and the QR rendering contract. The hosted-bundle R test
checks inclusion of all three QR scripts without expanding the private whitelist.

`python tests/browser/check_teacher_qr.py [teacher-url]` checks the authenticated
flow, independent QR decoding, downloaded PNG, fullscreen, tab navigation, mobile
layout, clipboard and logout. It requires Python Playwright, Pillow and `zxing-cpp`
(development checks only). Credentials are read from the ignored hosting file and
are never printed. The checker does not open or submit the Qualtrics survey.
