#!/usr/bin/env bash
# Demo/test tour of the Dynamic Island effects — run and watch the screen.
# Each step announces itself, fires, then waits so the effect can play out.
set -u

step() {
    echo
    echo "==> $1"
    sleep "${2:-3}"
}

echo "Island demo — garde les yeux sur le haut de l'écran."

step "Notification normale : comètes sur les bords + morph jelly + shine de la pilule + banner" 0
notify-send -a "Signal" "Alice" "Salut, dispo ce soir ?"
sleep 4

step "Notification critique : comètes ROUGES + banner à liseré rouge (persistante)" 0
notify-send -u critical -a "Batterie" "Niveau critique (démo)" "Ceci reste affiché jusqu'à dismiss"
sleep 4

step "Groupe : 3 notifs de la même app → badge ×3 sur le banner" 0
for i in 1 2 3; do notify-send -a "Telegram" "Maman" "Message $i"; sleep 0.4; done
sleep 4

step "Inline reply : notif de chat avec champ de réponse (banner + panneau)" 0
gdbus call --session --dest org.freedesktop.Notifications \
    --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.Notify \
    "TestChat" 0 "internet-chat" "Bob" "Tu peux répondre inline ici" \
    '["inline-reply", "Répondre", "default", "Ouvrir"]' '{}' 8000 >/dev/null
sleep 5

step "Presenter volume : pilule fixe 320px + barre + glyphe spring-in" 0
wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%+
sleep 0.8
wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-
sleep 3

step "Splash court puis long : la pilule se moule au texte et morphe entre les deux" 0
dms ipc call inhibit toggle >/dev/null
sleep 2.8
dms ipc call inhibit toggle >/dev/null
sleep 3

step "Son de notification par-dessus la musique (si un média joue, tu dois l'entendre)" 0
notify-send -a "SoundCheck" "Ding" "Le son doit passer par-dessus le média"
sleep 3

step "Activité live : pilule chip avec progression (island-run)" 0
dms ipc call island activityStart "demo" "Démo en cours" "rocket_launch" >/dev/null
for p in 20 45 70 90 100; do
    dms ipc call island activityProgress "demo" "$p" >/dev/null
    sleep 0.7
done
dms ipc call island activityDone "demo" "Démo terminée" >/dev/null
sleep 3

step "Panneaux : notifications (onglets Actives/Historique) puis tray (lignes + menus)" 0
dms ipc call island open notifications >/dev/null
sleep 3
dms ipc call island open tray >/dev/null
sleep 3
dms ipc call island close >/dev/null

echo
echo "Fin. À tester à la souris : hover de la pilule (idle pane + chip tray),"
echo "reply inline dans le banner, swipe d'un banner vers la droite."
