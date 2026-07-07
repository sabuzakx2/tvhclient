# TVH Stream

TVHeadend용 Android / Android TV 라이브 시청 앱입니다.

## 기능

- 넷플릭스 스타일의 어두운 홈 화면과 가로 채널 레일
- 채널 태그, 채널 그리드, Now(현재 방송), 즐겨찾기
- TVHeadend EPG 기반 현재 방송 진행률
- 채널별 전체 EPG와 실시간 재생 화면
- Android TV D-pad 포커스, 선택키 재생
- 앱 내부 즐겨찾기 저장
- GitHub Actions APK 자동 빌드

## 설치와 빌드

1. 이 폴더 전체를 GitHub 저장소에 업로드합니다.
2. `main` 브랜치로 push합니다.
3. GitHub **Actions → Build Android APK**에서 완료된 실행을 엽니다.
4. Artifacts의 `tvh-stream-release-apk`를 받아 설치합니다.

태그 `v1.0.0`처럼 push하면 GitHub Release에도 APK가 등록됩니다.

## 첫 실행 설정

- 서버 주소: `http://NAS_IP:9981`
- 사용자명 / 비밀번호: TVHeadend 웹 UI 로그인 계정
- 스트리밍 프로파일: 비워두면 TVHeadend 기본 프로파일을 사용합니다.

## 주의

외부망 시청은 직접 포트를 공개하지 말고 WireGuard 같은 VPN으로 NAS 내부망에 연결한 뒤 사용하는 방식을 권장합니다.
