// Player-to-player chat (GIF-33) — the Phoenix Channel + fetch() replacement for
// `Web/wwwroot/Global.js`'s jQuery/SignalR chat client. Floating chat windows, the
// `/Home/Chat` / `/Home/LoadChatMessages` / `/Home/CloseChatWindow` endpoints, and the
// `"chat:<account id>"` push topic all mirror the legacy behavior (see
// `GlobalCombatWeb.ChatChannel`'s moduledoc) — only the transport (jQuery+SignalR -> fetch+
// Phoenix Channel) and DOM APIs are modernized.
import {Socket} from "phoenix"

function csrfToken() {
  const meta = document.querySelector("meta[name='csrf-token']")
  return meta ? meta.getAttribute("content") : null
}

function postForm(path, params) {
  const body = new URLSearchParams(params)
  return fetch(path, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      "x-csrf-token": csrfToken(),
    },
    body,
  })
}

let windowCount = 0

function appendChatMessage(sourceId, sourceName, text) {
  const existing = document.querySelector(`[data-chat-window][data-partner-id="${sourceId}"]`)
  if (!existing) {
    popupChat(sourceId, sourceName)
    playChime()
  } else {
    const area = existing.querySelector(".chat-area")
    const line = document.createElement("div")
    line.innerHTML = `<b></b> `
    line.querySelector("b").textContent = sourceName + ":"
    line.append(" " + text)
    area.appendChild(line)
    area.scrollTop = area.scrollHeight
  }
}

function playChime() {
  const audio = document.getElementById("notify")
  if (audio) audio.play().catch(() => {})
}

function popupChat(partnerId, partnerName) {
  if (document.querySelector(`[data-chat-window][data-partner-id="${partnerId}"]`)) return

  windowCount += 1
  const box = document.createElement("div")
  box.className = "chatbox"
  box.dataset.chatWindow = "true"
  box.dataset.partnerId = partnerId
  box.dataset.partnerName = partnerName
  box.style.right = `${10 + (windowCount - 1) * 225}px`
  box.innerHTML = `
    <div class="chat-header">
      <span>${partnerName}</span>
      <button type="button" class="chat-close" aria-label="Close">×</button>
    </div>
    <div class="chat-area"></div>
    <div class="chat-compose">
      <textarea rows="2"></textarea>
    </div>
  `
  document.body.appendChild(box)

  box.querySelector(".chat-close").addEventListener("click", () => {
    box.remove()
    postForm("/Home/CloseChatWindow", {targetId: partnerId, targetName: partnerName})
  })

  const textarea = box.querySelector("textarea")
  textarea.addEventListener("keypress", e => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault()
      const message = textarea.value
      if (!message.trim()) return
      postForm("/Home/Chat", {targetId: partnerId, message}).then(() => {
        appendChatMessage(partnerId, "Me", message)
        textarea.value = ""
      })
    }
  })

  postForm("/Home/LoadChatMessages", {targetId: partnerId, targetName: partnerName})
    .then(r => r.json())
    .then(history => history.forEach(m => appendChatMessage(partnerId, m.name, m.text)))
}

function connectChatSocket() {
  const meta = document.querySelector("meta[name='chat-token']")
  const topicMeta = document.querySelector("meta[name='chat-topic']")
  if (!meta || !topicMeta) return

  const socket = new Socket("/socket", {params: {token: meta.getAttribute("content")}})
  socket.connect()

  const channel = socket.channel(topicMeta.getAttribute("content"), {})
  channel.on("receive_message", ({source_id, source_name, text}) =>
    appendChatMessage(source_id, source_name, text)
  )
  channel.join()

  window.gameChatChannel = channel
}

function reopenSavedWindows() {
  const meta = document.querySelector("meta[name='open-chat-windows']")
  if (!meta) return

  JSON.parse(meta.getAttribute("content")).forEach(({id, name}) => popupChat(id, name))
}

document.addEventListener("click", e => {
  const trigger = e.target.closest(".chat-open-btn")
  if (!trigger) return
  popupChat(trigger.dataset.accountId, trigger.dataset.accountName)
})

document.addEventListener("DOMContentLoaded", () => {
  connectChatSocket()
  reopenSavedWindows()
})
