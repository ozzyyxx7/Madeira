# 개인 Madeira 포크 작업 메모

이 공개 포크는 `willfaust/Madeira`의 `v0.1.3`에서 시작했다. `main`은 공식 소스를 따라가고, `personal`은 개인 변경을 보관한다. 평소 수정은 `personal`에서 진행한다.

게임별 기록: [Mirror's Edge](MIRRORS_EDGE.md), [Elf Girl Pinball](ELF_GIRL_PINBALL.md).

## 공식 앱과 함께 설치

`personal` 브랜치의 iOS 앱 이름은 **Madeira Dev**이고, 기본 번들 ID는 `com.ozzyyxx7.madeira.personal`이다. 이 iPad에 실제 설치해 테스트한 앱은 서명 시 `MADEIRA_BUNDLE_IDENTIFIER=com.ozzyyxx7.madeira.personal.2VVL5732XF`를 지정했다. 덮어 설치할 때는 **이 전체 ID**를 다시 사용해야 데이터가 유지된다. JIT Helper는 이 ID 아래의 별도 확장으로 빌드된다. 단축어가 앱으로 돌아오는 URL scheme도 `madeira-ozzyyxx7`로 분리했다. 공식 앱과 설치 공간 및 게임 데이터가 분리되므로, 별도로 옮기지 않은 게임과 설정은 새 개인 빌드에 나타나지 않는다.

이 iPad Air에는 공식 앱에서 `madeira.cfg`, 컨트롤·입력·라이브러리 JSON, 표시 설정을 **한 번 복사**했다. 기존 기기 페어링 파일도 Madeira Dev가 자체 Keychain으로 가져온 것을 로그에서 확인했다. 공식 앱과 개인 앱의 저장 공간은 계속 분리되어 있으므로 이후 설정 변경은 자동으로 동기화되지 않는다. 새 Madeira Dev IPA를 같은 번들 ID와 Apple 팀으로 덮어 설치하면 개인 앱의 설정은 유지된다. Steam 로그인 토큰은 앱별 Keychain에 있어서 개인 앱에서 다시 로그인해야 한다. 페어링 파일과 토큰은 Git에 넣지 않는다.

Xcode 프로젝트에 원 개발자의 Development Team을 남기지 않았다. 실제 서명에는 자신의 Apple 계정/팀을 Xcode 또는 사이드로드 도구에서 지정한다. Apple ID, 인증 코드, 기기 pairing plist, 서명 키, 게임 파일과 로그는 공개 저장소에 올리지 않는다.

## 새 작업 시작

```sh
git switch personal
git pull --ff-only origin personal
git submodule update --init --recursive
```

개별 기능은 `personal`에서 작업 브랜치를 만든 뒤 수정하고, 검증 후 `personal`에 병합한다. 변경 전에 `git status`로 현재 브랜치와 새 파일을 확인한다.

## 공식 버전 받아오기

공식 릴리스가 나오면 먼저 현재 작업을 커밋하고 다음 순서로 통합한다. `vNEW`는 실제 공식 태그로 바꾼다.

```sh
git fetch upstream --tags
git switch personal
git switch -c update-vNEW
git merge vNEW
git submodule update --init --recursive
```

충돌이 나면 개인 앱 식별자, JIT callback URL, 개인 기능을 확인하면서 해결한다. 빌드와 기기 실행을 확인한 뒤 통합 브랜치를 `personal`에 반영한다.

```sh
git switch personal
git merge --ff-only update-vNEW
git push origin personal
```

공식 코드만 담는 `main`은 별도로 `git switch main && git pull --ff-only upstream main && git push origin main`으로 동기화한다. `personal`을 공식 코드로 덮어쓰지 않는다.

## FEX 서브모듈

`personal`은 `FEX` 서브모듈을 공개 포크 `ozzyyxx7/FEX`의 `personal-ios` 브랜치 커밋으로 고정한다. FEX 소스를 수정할 때는 `FEX` 안에서 커밋하고 그 브랜치를 먼저 푸시한 다음, 상위 Madeira 저장소에서 변경된 서브모듈 포인터를 커밋한다. FEX의 공식 원격 저장소는 서브모듈 안의 `upstream`이다. 새 공식 Madeira 릴리스를 병합할 때 FEX 포인터 충돌이 나면 공식 변경을 FEX 포크에 먼저 통합하고 상위 저장소 포인터를 새 커밋으로 갱신한다.

## 빌드 준비 상태

이 Mac에는 Xcode 27과 Metal Toolchain, Homebrew 빌드 도구, Rust iOS 타깃, llvm-mingw, iOS용 LLVM, FFmpeg, GnuTLS, FreeType, Wine/FEX/DXMT 정적 라이브러리, Microsoft VC 런타임을 준비했다. 이 중 `toolchains/`, 컴파일 결과물, VC DLL은 공개 Git 저장소에 들어가지 않는다. 깨끗한 새 체크아웃이나 다른 Mac에서는 [`BUILDING.md`](BUILDING.md)에 따라 다시 마련해야 한다. 기기별 페어링 파일과 Apple 서명 정보도 Git에 넣지 않는다.

현재 Mac에서 서명 없는 Debug 빌드를 확인할 때 사용한 명령:

```sh
git switch personal
git submodule update --init --recursive
bash build/madeira-dock/build.sh
bash build/stage-licenses.sh
xcodebuild -project app/Madeira.xcodeproj -scheme Madeira \
  -configuration Debug -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

기기에 설치할 때는 개인 Apple 팀으로 서명해야 한다. Release 구성은 공식 빌드 문서에 게임 실행 중 충돌 가능성이 기록되어 있으므로 Debug를 사용한다. 앱 번들 ID와 JIT Helper ID가 개인용으로 분리되어 있어 공식 Madeira와 동시 설치할 수 있다.

Memory+는 앱 소스의 entitlement 선언만으로 켜지지 않는다. 설치된 앱의 개발용 provisioning profile에도 `com.apple.developer.kernel.increased-memory-limit`가 있어야 한다. AltServer가 새 개인 앱 ID를 처음 만들면 이 권한이 빠질 수 있다. 이 Mac의 Xcode에 설치 때 사용한 Apple 계정이 연결되어 있다면, **이미 설치된 개인 앱의 전체 bundle ID**를 `MADEIRA_BUNDLE_IDENTIFIER`에 지정하고 해당 계정의 Personal Team으로 자동 서명 빌드한다. 완성된 `Madeira.app/embedded.mobileprovision`에서 Memory+ 권한과 `get-task-allow`를 확인한 뒤 같은 bundle ID로 덮어 설치한다. 새 bundle ID로 설치하면 앱 데이터와 Steam 로그인을 다시 준비해야 한다.

`dockhost.exe`가 없으면 앱은 Madeira Dock 메뉴를 숨긴다. IPA를 만들기 전에 `build/madeira-dock/build.sh`를 실행하고, 완성된 앱의 `arm64ec-windows/dockhost.exe`가 실제로 포함됐는지 확인한다.

## 32비트 게임과 번들 누락 검사

미러스 엣지 테스트의 수정 이력, 현재 충돌 지점, 공식 앱 비교 및 이후 재조사 순서는 [`MIRRORS_EDGE.md`](MIRRORS_EDGE.md)에 따로 기록했다. 현재 게임은 실행되지 않으며, 이 문서의 번들 검사는 게임 호환성 판정이 아니다.

미러스 엣지처럼 32비트 게임을 실행하려면 `app/Madeira/i386-windows/`가 실제 Wine DLL들로 채워져 있어야 한다. 이 폴더의 바이너리는 Git에서 제외되며, 깨끗한 체크아웃에는 `.gitkeep`만 있다. Xcode는 빈 폴더여도 빌드에 성공하므로, 빌드 전에 `build/wine-i386/build.sh`를 실행하고 적어도 `ntdll.dll`, `kernel32.dll`, `d3d9.dll`이 있는지 확인한다. 2026-10-12 이 Mac에서는 공식 0.1.3 IPA의 i386 파일 729개를 현재 빌드에 복원했다. 소스에서 다시 만들려면 [`WOW64.md`](WOW64.md)의 빌드 순서를 따른다.

```sh
test -f app/Madeira/i386-windows/ntdll.dll
test -f app/Madeira/i386-windows/kernel32.dll
test -f app/Madeira/i386-windows/d3d9.dll
python3 build/tools/audit-bundle.py /path/to/Madeira-0.1.3.ipa /path/to/Madeira.app
python3 build/tools/check-pe-imports.py app/Madeira \
  --objdump toolchains/llvm-mingw-20260421-ucrt-macos-universal/bin/llvm-objdump
```

첫 Python 명령은 공식 IPA의 앱 파일이 개인 빌드에 빠졌는지 전수 비교한다. 개인 앱의 실행 코드·서명·프레임워크와 재빌드한 라이브러리는 내용이 달라도 목록에만 표시되며, 공식 파일 누락 시 종료 코드 1을 반환한다. 두 번째 명령은 세 Windows 바이너리 폴더의 직접 DLL 참조를 확인한다. 2026-10-12 비교에서 공식 파일 누락과 DLL 참조 누락은 모두 0개였다. 공식 IPA의 `plugplay.exe`, `svchost.exe`, `winedevice.exe`도 로컬 번들에 복원했지만 현재 iOS 실행 경로에서는 사용하지 않는다. 추가로 ARM64EC `bthprops.cpl`이 참조하는 `bluetoothapis.dll`을 Wine 소스에서 빌드해 넣어 ARM64EC DLL 참조 누락을 없앴다.

개인 브랜치의 `build/fex-ios/build.sh`는 iOS용 CMake toolchain과 내장 의존성을 사용하며, `build/wineserver/build.sh`는 기본 정적 아카이브가 없으면 소스에서 만든다. Wine 빌드 전에 `wine/build-macos`와 `wine/build-arm64ec`를 구성하고 필요한 IDL 헤더를 생성해야 한다.

`build/dxmt-ios/build.sh`는 Xcode 27에서 Metal 셰이더를 빌드하기 위해 생성 입력에 호환 수정을 적용한다. DXMT 소스 서브모듈은 수정하지 않는다. 이 스크립트로 `libdxmt_unix.a`를 만든 뒤 [`build/dxmt-ios/README.md`](../build/dxmt-ios/README.md)의 `libtool` 명령으로 `libdxmt_combined.a`를 생성해야 한다.

FEX의 iOS 호스트 정적 라이브러리와 ARM64EC `xtajit64.dll` 모두 이 Mac에서 빌드됐다. 현재 llvm-mingw에서는 ARM64EC Thin LTO와 C++ 런타임 링크가 함께 실패해 `build/fex-arm64ec/build.sh`에서 LTO를 껐다. 스크립트를 실행하면 앱에 보관된 DLL이 교체되므로, 기기에서 확인한 뒤 바이너리 변경을 커밋한다.
