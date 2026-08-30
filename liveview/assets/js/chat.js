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

// Shared assertive live region: announces a newly-opened chat window (triggered by an
// incoming DM, not by the user clicking to open it) without moving focus away from
// whatever the user is doing. Reused across calls — role="alert" only reliably announces
// on *content changes* to a node already in the DOM, not on simultaneous insert+populate.
function announce(text) {
  let el = document.getElementById("chat-announcer")
  if (!el) {
    el = document.createElement("div")
    el.id = "chat-announcer"
    el.className = "sr-only"
    el.setAttribute("role", "alert")
    el.setAttribute("aria-live", "assertive")
    el.setAttribute("aria-atomic", "true")
    document.body.appendChild(el)
  }
  el.textContent = text
}

function appendChatMessage(sourceId, sourceName, text) {
  const existing = document.querySelector(`[data-chat-window][data-partner-id="${sourceId}"]`)
  if (!existing) {
    popupChat(sourceId, sourceName)
    announce(`New message from ${sourceName}`)
    playChime()
  } else {
    const area = existing.querySelector(".chat-area")
    const line = document.createElement("div")
    const name = document.createElement("b")
    name.textContent = sourceName + ":"
    line.append(name, " " + text)
    area.appendChild(line)
    area.scrollTop = area.scrollHeight
  }
}

function playChime() {
  const audio = document.getElementById("notify")
  if (audio) audio.play().catch(() => {})
}

// `focusCompose: true` marks a window opened as a direct result of user action (the
// `.chat-open-btn` click path) — focus moves into the textarea. Windows opened because a
// message arrived leave focus alone; see `announce()` for how those are surfaced instead.
function popupChat(partnerId, partnerName, {focusCompose = false} = {}) {
  const existing = document.querySelector(`[data-chat-window][data-partner-id="${partnerId}"]`)
  if (existing) {
    if (focusCompose) existing.querySelector("textarea")?.focus()
    return existing
  }

  windowCount += 1
  const box = document.createElement("div")
  box.className = "chatbox"
  box.dataset.chatWindow = "true"
  box.dataset.partnerId = partnerId
  box.dataset.partnerName = partnerName
  box.style.right = `${10 + (windowCount - 1) * 225}px`
  box.setAttribute("role", "dialog")
  box.setAttribute("aria-label", partnerName)

  const header = document.createElement("div")
  header.className = "chat-header"
  const title = document.createElement("span")
  title.textContent = partnerName
  const closeBtn = document.createElement("button")
  closeBtn.type = "button"
  closeBtn.className = "chat-close"
  closeBtn.setAttribute("aria-label", "Close")
  closeBtn.textContent = "×"
  header.append(title, closeBtn)

  const area = document.createElement("div")
  area.className = "chat-area"
  area.setAttribute("role", "log")
  area.setAttribute("aria-relevant", "additions")

  const compose = document.createElement("div")
  compose.className = "chat-compose"
  const textarea = document.createElement("textarea")
  textarea.rows = 2
  textarea.setAttribute("aria-label", `Message to ${partnerName}`)
  compose.appendChild(textarea)

  box.append(header, area, compose)
  document.body.appendChild(box)

  closeBtn.addEventListener("click", () => {
    box.remove()
    postForm("/Home/CloseChatWindow", {targetId: partnerId, targetName: partnerName})
  })

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

  if (focusCompose) textarea.focus()

  postForm("/Home/LoadChatMessages", {targetId: partnerId, targetName: partnerName})
    .then(r => r.json())
    .then(history => {
      history.forEach(m => appendChatMessage(partnerId, m.name, m.text))
      // Enable aria-live only after the history backlog is in place, so opening a chat
      // doesn't read the whole conversation aloud — only genuinely new messages announce.
      area.setAttribute("aria-live", "polite")
    })

  return box
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
  popupChat(trigger.dataset.accountId, trigger.dataset.accountName, {focusCompose: true})
})

document.addEventListener("DOMContentLoaded", () => {
  connectChatSocket()
  reopenSavedWindows()
})
