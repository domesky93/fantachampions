// js/views/live.js - Vista Voti Live e Calendario
import { supabase } from '../api.js';
import { getLiveScores } from '../fixtures.js';

export async function renderLiveView(container, matchday = 1) {
    container.innerHTML = `
        <div class="p-6 max-w-4xl mx-auto">
            <h2 class="text-2xl font-bold mb-4">🔴 Voti Live & Calendario - Giornata ${matchday}</h2>
            <div id="live-scores-list" class="space-y-3">
                <p class="text-gray-500">Caricamento voti in corso...</p>
            </div>
        </div>
    `;

    const scores = await getLiveScores(matchday);
    const listContainer = container.querySelector('#live-scores-list');

    if (scores.length === 0) {
        listContainer.innerHTML = `<p class="text-gray-500 italic">Nessun voto live disponibile per questa giornata.</p>`;
        return;
    }

    listContainer.innerHTML = scores.map(s => `
        <div class="flex justify-between items-center p-4 bg-white border rounded shadow-sm">
            <div>
                <span class="font-bold text-lg">Giocatore ID: ${s.player_id}</span>
                <span class="text-sm text-gray-500 block">Gol: ${s.goals} | Ammonizioni: ${s.yellow_cards} | Espulsioni: ${s.red_cards}</span>
            </div>
            <div class="text-xl font-extrabold text-green-600">
                ${s.vote}
            </div>
        </div>
    `).join('');
}
