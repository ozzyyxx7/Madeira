# 개인 Madeira 포크 작업 메모

이 공개 포크는 `willfaust/Madeira`의 `v0.1.3`에서 시작했다. `main`은 공식 소스를 따라가고, `personal`은 개인 변경을 보관한다. 평소 수정은 `personal`에서 진행한다.

## 공식 앱과 함께 설치

`personal` 브랜치의 iOS 앱 이름은 **Madeira Dev**이고, 번들 ID는 `com.ozzyyxx7.madeira.personal`이다. JIT Helper는 이 ID 아래의 별도 확장으로 빌드된다. 단축어가 앱으로 돌아오는 URL scheme도 `madeira-ozzyyxx7`로 분리했다. 공식 앱과 설치 공간 및 게임 데이터가 분리되므로, 개인 빌드에서는 Steam 로그인과 게임 설치, JIT 설정을 다시 해야 한다.

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

## 빌드 준비 상태

서브모듈은 내려받았지만, 깨끗한 체크아웃만으로는 아직 앱이 빌드되지 않는다. [`BUILDING.md`](BUILDING.md)의 외부 입력, llvm-mingw, iOS용 LLVM, 누락된 정적 라이브러리, Microsoft VC 런타임이 필요하다. 일부 공식 빌드 절차도 새 Mac에서 재검증되지 않았다. Xcode 약관 동의와 빌드 도구 설치가 끝나면 해당 문서를 따라 Debug 구성으로 빌드한다. Release 구성은 공식 문서상 게임 실행 중 충돌할 수 있다.
