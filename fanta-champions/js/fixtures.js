// js/fixtures.js - Gestione calendario reale e avversari
import { sb } from './api.js';

export async function getPlayerNextFixture(teamName, matchday) {
    if (!teamName) return "Riposo / N.D.";
    try {
        const { data, error } = await sb
            .from('real_fixtures')
            .select('*')
            .eq('matchday', matchday)
            .or(`home_team.ilike.%${teamName}%,away_team.ilike.%${teamName}%`)
            .single();

        if (error || !data) return "Nessuna partita";

        const isHome = data.home_team.toLowerCase().includes(teamName.toLowerCase());
        const opponent = isHome ? data.away_team : data.home_team;
        return `vs ${opponent} (${isHome ? 'Casa' : 'Trasferta'})`;
    } catch (e) {
        console.error("Errore recupero fixture:", e);
        return "Info non disp.";
    }
}

export async function getLiveScores(matchday) {
    try {
        const { data, error } = await sb
            .from('live_scores')
            .select('*')
            .eq('matchday', matchday);

        if (error) throw error;
        return data || [];
    } catch (e) {
        console.error("Errore recupero voti live:", e);
        return [];
    }
}
