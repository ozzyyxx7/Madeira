# Mirror's Edge (Steam App ID 17410) 테스트 인계 기록

기록일: 2026-10-12. 이 테스트는 여기서 중단했다. 현재 결론은 **게임을 실행하는 데 실패한다**는 것이다. Madeira Dev의 32비트 실행에 필요했던 파일 누락과 시작 지연은 해결했지만, Mirror's Edge 자체는 시작 직후 예외를 내고 종료된다. 아래의 예외가 왜 발생하는지는 아직 확인하지 못했다.

## 테스트 범위와 환경

- 기기: 케이블로 연결한 iPad Air M3. 공식 Madeira와 별도 식별자의 Madeira Dev를 동시에 설치했다. 두 앱의 Steam/Wine 데이터는 별개다.
- 소스: 이 저장소의 `personal` 브랜치. 기준 공식 배포물은 Madeira 0.1.3 IPA다. 개인 앱은 Xcode Debug로 서명해 덮어 설치했고, 같은 앱 식별자를 유지해 Dev의 게임 데이터를 보존했다.
- 게임: Steam의 Mirror's Edge, `MirrorsEdge.exe`는 **32비트 x86 PE**. 실행에는 i386 Wine 파일, WoW64, FEX x86 번역, JIT가 모두 관여한다. 이 때문에 일반 ARM64EC 게임보다 오류 지점이 많지만, 아래의 남은 예외를 단순히 “32비트라서”라고 단정할 근거는 없다.
- 관찰 설정: Dev 앱의 JIT를 켜고 `One-time installs`는 **Skip**으로 실행했다. 마지막 테스트 후 `d3d9 = native` 시험 설정은 제거했다. 당시 Dev의 `madeira.cfg`에는 `env.MADEIRA_WOW_SMALL_VA_SLOTS = 4`가 남아 있었다. 공식 앱과 Dev 앱의 설치 상태는 같지 않았다.

## 확인한 순서와 결과

| 단계 | 증거와 처리 | 결과 |
| --- | --- | --- |
| Dev의 최초 32비트 기동 | `app/Madeira/i386-windows/`에 `.gitkeep`만 있어서 `ntdll.dll` 탐색이 `0xc0000135`로 실패했다. 공식 0.1.3 IPA의 i386 파일 729개를 로컬 번들에 복원했다. | i386 `ntdll.dll`을 찾고 게임 프로세스까지 진입했다. 복원 바이너리는 Git에서 제외된다. |
| 번들 전수 검사 | `build/tools/audit-bundle.py`로 공식 IPA와 Dev 앱의 파일 목록을 비교했고, `build/tools/check-pe-imports.py`로 i386·ARM64·ARM64EC Windows 바이너리의 직접 DLL 참조를 검사했다. | 공식 파일 누락 0개, 직접 DLL 참조 누락 0개. 이는 실행 시 모든 의존성이 정상이라는 보증은 아니다. |
| Wine 기동 | iOS에서 첫 `pipe2()` 호출이 서명된 Dev 앱을 종료시켜 `server_pipe()`의 iOS 경로를 `pipe()`와 `fcntl`로 바꿨다. `virtual_set_large_address_space()`가 iOS에서 매핑 불가능한 4GB 아래를 반복 검색하지 않도록 시작 주소를 보정했다. | Wine와 i386 자식 프로세스가 이전보다 진행했다. 이 두 변경은 다른 게임에도 영향을 주므로 다음 게임에서 회귀 여부를 관찰해야 한다. |
| 시작 화면 | 초기 일회성 설치의 Windows Installer 보조 프로세스 창이 시작 화면 뒤에 숨을 수 있어, 해당 **초기** 창은 `Show desktop`에 노출하도록 했다. | PhysX 설치 창을 볼 수 있었다. 이 수정이 게임 충돌을 해결하지는 않는다. |
| PhysX 설치 시도 | 설치 UI에서 동의/설치를 눌렀으나 여러 분간 진행되지 않았고, 한 시도에서는 `Failed to create thread`가 나타났다. 이후 `One-time installs = Skip`으로 테스트했다. | Dev 로그에서 DirectX·PhysX·VC 재배포 패키지가 `pending`이다. 공식 앱 로그에서는 PhysX와 VC가 `done`이다. 두 앱의 설치 상태가 달라 직접적인 A/B 비교에는 한계가 있다. |
| 최종 실행 | Dev 로그에서 `PhysXExtensions.dll`과 게임 바이너리까지 로드된다. `GameExplorerImpl_VerifyAccess` 뒤 `0xe06d7363` C++ 예외가 기록되고, 이어 `0xc0000005` 접근 위반 후 자식 프로세스가 끝난다. | 게임 화면으로 넘어가지 않았다. `GameExplorerImpl_VerifyAccess`의 `fixme` 로그나 PhysX `pending`만으로 원인을 특정할 수 없다. |
| D3D9 비교 | Dev 설정에 임시로 `d3d9 = native`를 넣어 다시 실행했다. | 같은 C++ 예외와 접근 위반이 나왔다. 시험 설정은 원복했다. |
| 공식 앱 비교 | 공식 앱 실행 로그도 게임 바이너리 로드 뒤 같은 `0xe06d7363` C++ 예외를 기록한다. 이어 `0xc0000005`로 종료한다. | 남은 실패는 Dev에서만 생긴 현상으로 볼 수 없다. 양쪽의 접근 위반 주소와 설치 상태는 서로 다르므로 **동일한 근본 원인**이라고 확정하지 않는다. |

대표적인 로그 지점은 아래와 같다. 주소와 스레드 번호는 실행마다 변할 수 있다.

```text
Dev:      Load module PhysXExtensions.dll
Dev:      GameExplorerImpl_VerifyAccess (...MirrorsEdge.exe...)
Dev:      [exc-disp] ... code=e06d7363 ...
Dev:      [exc-disp] ... code=c0000005 ...
Official: GameExplorerImpl_VerifyAccess (...MirrorsEdge.exe...)
Official: [exc-disp] ... code=e06d7363 ...
Official: ... exit_code=0xc0000005
```

Mac의 임시 원본 로그 이름은 `/tmp/madeira-dev-complete-run-later3.txt`, `/tmp/madeira-dev-native-d3d9-retry.txt`, `/tmp/madeira-log-next-test-2.txt`였다. `/tmp` 파일은 사라질 수 있으며 개인정보나 토큰이 포함될 수 있어 저장소에는 넣지 않았다. 위 요약은 필요한 상태 코드만 남긴 것이다.

## 현재 소스와 기기 상태

- 이 인계 기록과 함께 소스에는 iOS `server_pipe()` 처리, 32비트 주소 공간 시작점 보정, `NtReadVirtualMemory()`의 안전한 자기 프로세스 읽기, 일회성 설치 보조 창 노출과 호스트 테스트를 보관한다. 메모리 읽기 변경은 예외 후 충돌 덤프를 읽다가 생기는 **2차 호스트 충돌**을 피하려는 것으로, 최초 C++ 예외를 해결했다는 뜻이 아니다.
- 추가했던 `[child-boot]`, `[wow-ntdll]`, `[va-scan]` 진단 출력과 설치하지 않은 C++ 예외 타입 판독 실험은 소스에서 제거했다. 이후 게임을 위한 로컬 빌드는 이 정리된 소스를 기준으로 한다.
- iPad에 마지막으로 설치되어 실제 테스트한 Madeira Dev는 정리 전의 진단 빌드다. 위의 C++ 예외 타입 판독 빌드는 **설치하지 않았다**. 소스 정리만으로 iPad 앱이 자동 갱신되지는 않는다.
- `app/Madeira/i386-windows/`의 729개 파일 및 다른 로컬 바이너리, Apple 서명 자격, 게임 파일, pairing 파일, 원본 로그는 공개 Git에 없다. 다른 Mac에서 `personal` 브랜치를 받아도 i386 번들을 다시 준비해야 한다. [`PERSONAL_FORK.md`](PERSONAL_FORK.md)와 [`WOW64.md`](WOW64.md)를 참고한다.

## 언젠가 이 게임을 다시 조사할 경우

1. 현재 앱/소스/설정 및 `One-time installs` 상태를 기록한다. 공식과 Dev의 PhysX·VC 설치 상태를 맞추지 않은 비교는 원인 판별에 쓸 수 없다.
2. 먼저 `0xe06d7363`의 throw 지점과 C++ 타입·호출 스택을 안전하게 확인한다. `GameExplorerImpl_VerifyAccess` 뒤에 찍힌다는 사실만으로 그 함수가 원인인 것은 아니다.
3. 예외가 무해하게 처리되는지, 혹은 처리되지 않아 `0xc0000005`로 이어지는지 확인한다. 게스트 주소 창과 호스트 주소를 구분해 예외/메모리 로그를 해석한다.
4. 게임의 PhysX 초기화와 필요 런타임을 설치 완료 상태에서 별도로 확인한다. `PhysXExtensions.dll` 로드 자체는 정상 초기화의 증거가 아니다.
5. 미러스 엣지용 임시 설정이 다른 게임의 기준 설정에 남지 않았는지 확인한다. 현재의 `MADEIRA_WOW_SMALL_VA_SLOTS = 4`는 사용자 Dev 설정이며, 새 게임 문제를 분석할 때 함께 기록한다.

다음 게임은 별도의 실행 결과와 로그로 조사한다. 이 문서의 Mirror's Edge 예외를 다른 게임의 원인으로 추정하지 않는다.
