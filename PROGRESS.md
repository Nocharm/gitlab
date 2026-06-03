# Progress

프로젝트 진행 현황 로그. 커밋 직전 갱신한다 (`rules/common/git.md` 규칙).

## 2026-06-03

- 템플릿(claude-code-template)에서 프로젝트 부트스트랩. Python+Docker 스택에 맞춰
  `CLAUDE.md` import 정리(typescript 룰 제거), 템플릿 메타 문서(`docs/template/`) 제거.
  왜: 이 저장소를 71서버 GitLab Docker 배포 IaC로 전환.
- 루트 `README.md` placeholder → 프로젝트 개요로 교체. 왜: `documentation.md` 규칙상
  의미있는 커밋 전 README를 실제 내용으로 채워야 함.
- 설계 스펙 작성: `docs/superpowers/specs/2026-06-03-gitlab-docker-ci-deploy-design.md`.
  shell executor + 동적 포트 할당 + 데이터 라이프사이클(reset/destroy/purge) 합의.
  reconciler(repo 실삭제 자동 정리)는 다음 phase로 분리.
