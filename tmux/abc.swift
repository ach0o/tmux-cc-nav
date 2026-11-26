// 입력 소스를 그 사람의 영문 자판(ABC, U.S. 등)으로 바꿈. tmux에서 한글 상태로 prefix 키가 안 먹는 문제용
import Carbon
if let s = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() {
    TISSelectInputSource(s)
}
