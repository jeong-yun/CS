# OS 재설치 체크리스트

데이터 수집·분석 서버를 포맷하고 재설치할 때의 순서입니다.
핵심은 OS 설치가 아니라 **데이터 보존**과 **서비스 공백 관리**입니다.

---

## 0. 재설치가 필요한지 먼저 판단

재설치로 해결되는 문제인지 확인합니다. 디스크 증가·성능 저하 같은 증상은 설정을 고치지
않으면 새 OS에서도 동일하게 재발합니다. 정당한 사유: 커널·파일시스템 손상, 침해 대응,
OS EOL, 하드웨어 교체.

---

## 1. 현행 시스템 기록 (재설치 전, 가장 중요)

```bash
mkdir -p ~/backup
lsblk -f > ~/backup/lsblk.txt
cat /etc/fstab > ~/backup/fstab.txt
df -h > ~/backup/df.txt
getent passwd > ~/backup/passwd.txt       # 서비스·컨테이너용 UID 포함 ★
getent group  > ~/backup/group.txt
sudo cat /etc/sudoers /etc/sudoers.d/* > ~/backup/sudoers.txt      # ★
ip a; ip r; sudo firewall-cmd --list-all; chronyc sources > ~/backup/net.txt
cat /etc/os-release; uname -r > ~/backup/version.txt
rpm -qa | sort > ~/backup/rpm.txt
systemctl list-unit-files --state=enabled > ~/backup/svc.txt
ls -lR <DATA_ROOT> | head -2000 > ~/backup/perm.txt                # 소유자·권한 규격
```

문서에 없고 서버에만 존재하는 정보가 대상입니다 — 서비스 계정 UID/GID, 데이터 디스크
장치·레이블, 방화벽 허용 규칙, sudoers 구성.

---

## 2. 데이터 백업

| 대상 | 중요도 | 비고 |
|---|---|---|
| 데이터베이스 적재분 | 최상 | 정합성 있는 시점에 백업 |
| 수집 원본(`<DATA_ROOT>`) | 최상 | **별도 디스크면 재설치 시 건드리지 않는 것이 원칙** |
| 룰·대시보드·계정 설정 | 상 | UI의 내보내기 기능 활용 |
| 클러스터 상태(etcd/sqlite) | 상 | |
| PV 데이터, Secret/ConfigMap | 상 | `kubectl get ... -o yaml` |
| 파서·커스텀 설정 파일 | 중 | |

- 백업은 **외부 스토리지로**. 같은 서버에 두면 의미가 없습니다.
- 복원 테스트를 하지 않은 백업은 백업이 아닙니다. 최소한 `sha256sum`과 목록은 확인.

---

## 3. 디스크 파티션 전략

- **데이터 디스크가 OS와 분리돼 있으면** OS 디스크만 포맷하고 데이터 디스크는
  파티셔닝 대상에서 **명시적으로 제외**합니다. 설치 후 동일 레이블로 재마운트.
- 재설치는 레이아웃을 개선할 기회입니다. 컨테이너·로그가 루트 파티션을 채워 시스템
  전체가 마비되는 경로를 막으려면 **`/var`를 별도 파티션으로 분리**하는 것을 검토합니다.

---

## 4. 설치 후 기본 설정

```bash
ping -c2 1.1.1.1
sudo dnf update -y
sudo hostnamectl set-hostname <HOST>      # 점(.) 대신 하이픈 권장 (FQDN 오해 방지)
```

### 데이터 디스크 마운트

```bash
lsblk -f /dev/<DISK>                              # 기존 파일시스템 확인
sudo xfs_admin -L <LABEL> /dev/<PART>             # 레이블 부여 (재사용 시)
# (비우고 다시 쓸 때만) 대용량은 파일 삭제보다 재포맷이 빠르고 확실
sudo mkfs.xfs -f -L <LABEL> /dev/<PART>
blkid /dev/<PART>                                 # LABEL 확인 ★

sudo mkdir -p <DATA_ROOT>
echo '<LABEL 기반 fstab 한 줄>' | sudo tee -a /etc/fstab
# 예: LABEL=<LABEL>  <DATA_ROOT>  xfs  defaults,noatime  0 0
sudo systemctl daemon-reload
sudo umount <DATA_ROOT> && sudo mount <DATA_ROOT>  # fstab 기준으로 되는지 검증 ★
df -Th
```

- 식별자는 `/dev/sdX`(디스크 추가 시 밀릴 수 있음)보다 **LABEL 또는 UUID**를 씁니다.
- `noatime`: 읽기마다 접근시각을 기록하는 쓰기를 생략 — 로그·데이터 서버에서 I/O 절감.
- xfs는 부팅 시 fsck를 쓰지 않으므로 마지막 필드는 `0 0`.

### 불필요 파티션 정리

```bash
# 삭제 전 3중 확인
blkid /dev/<PART>
findmnt /boot                      # 지우려는 파티션이 아님을 확인
grep <PART> /etc/fstab             # 참조가 없어야 함
# 확인 후
sudo parted /dev/<DISK> rm <N>
sudo partprobe /dev/<DISK>
lsblk; swapon --show; timedatectl
sudo reboot
```

### 보안 기본

```bash
# 불필요한 관리 서비스 제거 (공격면 축소)
sudo dnf remove -y <불필요패키지>
sudo firewall-cmd --permanent --remove-service=<SERVICE> && sudo firewall-cmd --reload
ss -lntp | grep <PORT>             # 포트가 실제로 닫혔는지 검증 ★
sudo firewall-cmd --permanent --list-all
```

추가: SELinux 상태 확정, SSH 하드닝(키 인증·root 로그인 차단), NTP 동기화 확인.

---

## 5. 복원

1. **서비스 계정·UID/GID 재생성** — 1단계 기록과 동일하게.
   데이터 디렉터리 소유자 UID가 어긋나면 수집·적재 프로세스가 쓰기에 실패합니다. ★
2. sudoers 구성 복원 (`visudo -c`로 검증)
3. 데이터 디스크 재마운트 후 무결성 확인
4. 오케스트레이터 설치 → 워크로드 복원 → PV 연결
5. 라이선스·설정 파일 배치 (노드가 여러 대면 **모든 노드에**)
6. 수집 소스 등록, 룰 임포트

---

## 6. 검증

- 로그 인입 재개 (시간당 건수가 평소 수준인지)
- 파싱 정상 여부, 과거 데이터 조회 가능 여부
- 룰·경보 발생 테스트, 연동(메일·외부 시스템) 확인
- 파드 전원 `READY n/n`, RESTARTS 안정

---

## 7. 서비스 공백 관리 (기술 외 필수)

- 재설치 중 수집이 멈추며, **그 구간의 로그는 영구 소실**입니다.
- 작업 시간대는 트래픽 최저 시간으로. 가능하면 송신 측에서 큐잉하거나 대체 수집 경로 확보.
- **공백 시간대를 사전 공지하고 기록**합니다 (감사 시 "해당 시간 로그 없음"의 사유가
  문서로 남아야 함).
- 노드가 여러 대면 **한 대씩 순차 진행**하고, 첫 대의 전 과정을 기록해 다음 대의 절차서로 씁니다.
- 벤더 배포 영역(차트·이미지·라이선스)은 **공급사 지원을 받아** 복원하는 것이 정석입니다.
