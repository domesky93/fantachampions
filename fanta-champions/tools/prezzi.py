"""Genera il listone Fanta Champions con i prezzi (budget 300 per 18 giocatori).

Prezzo = valore della fascia x coefficiente del ruolo.
Fasce (scala attaccante): S=50 fuoriclasse, A=36 top, B=26 big, C=17 titolare forte,
D=11 titolare, E=7 rotazione/titolare squadra piccola, F=4 riserva/giovane.
Ruolo: A x1.0, C x0.85, D x0.7, P x0.6 (gli attaccanti portano più bonus).
Chi non ha una fascia scritta prende quella di default del livello della squadra;
i portieri non indicati (riserve) sono sempre F.
"""
import csv, sys, os
sys.path.insert(0, os.path.dirname(__file__))
from rosters import ROSTERS

TIER = {'S': 50, 'A': 36, 'B': 26, 'C': 17, 'D': 11, 'E': 7, 'F': 4}
ROLE_K = {'A': 1.0, 'C': 0.85, 'D': 0.7, 'P': 0.6}
POS = {'GK': 'P', 'DF': 'D', 'MF': 'C', 'FW': 'A'}

TOP = ['Paris Saint-Germain', 'Bayern Monaco', 'Real Madrid', 'Liverpool', 'Inter', 'Manchester City', 'Arsenal', 'Barcellona', 'Atlético Madrid']
LOW = ['Shakhtar Donetsk', 'Slavia Praga', 'Slovan Bratislava', 'AEK Atene', 'LASK', 'Viking', 'Sabah', 'Bodø/Glimt']
DEFAULT = lambda club: 'D' if club in TOP else 'F' if club in LOW else 'E'

# Ruolo fantacalcio diverso da Wikipedia (esterni offensivi = attaccanti)
ROLE_FIX = {
    'Jérémy Doku': 'A', 'Savinho': 'A', 'Antoine Semenyo': 'A', 'Rafael Leão': 'A', 'Leroy Sané': 'A',
    'Barış Alper Yılmaz': 'A', 'Giuliano Simeone': 'A', 'Yunus Akgün': 'A', 'Maximilian Beier': 'A',
    'Brajan Gruda': 'A', 'Ivan Perišić': 'D', 'Filip Kostić': 'D', 'Tajon Buchanan': 'A',
    'Geny Catamo': 'C', 'Maximiliano Araújo': 'D', 'Matteo Politano': 'A', 'Christos Tzolis': 'A',
    'Ademola Lookman': 'A', 'Rodrigo Riquelme': 'A', 'Chris Führich': 'A', 'Amad Diallo': 'C',
}

T = {}
def tier(level, names):
    for n in names.split(','):
        n = n.strip()
        if n:
            if n in T and T[n] != level: print('FASCIA DOPPIA:', n, T[n], '->', level, file=sys.stderr)
            T[n] = level

# ---------------- squadre top ----------------
tier('S', "Kylian Mbappé, Vinícius Júnior, Harry Kane, Erling Haaland, Lamine Yamal, Ousmane Dembélé, Khvicha Kvaratskhelia, Bukayo Saka, Lautaro Martínez, Raphinha, Michael Olise, Julián Álvarez, Alexander Isak")
tier('A', "Jude Bellingham, Federico Valverde, Jamal Musiala, Luis Díaz, Joshua Kimmich, Pedri, Florian Wirtz, Dominik Szoboszlai, Alexis Mac Allister, Hugo Ekitike, Cody Gakpo, Bradley Barcola, Phil Foden, Rayan Cherki, Rodri, Tijjani Reijnders, Antoine Semenyo, Viktor Gyökeres, Declan Rice, Martin Ødegaard, Eberechi Eze, Marcus Thuram, Nicolò Barella, Hakan Çalhanoğlu, Federico Dimarco, Alessandro Bastoni, Achraf Hakimi, Nuno Mendes, Vitinha, Désiré Doué, João Neves, Anthony Gordon, Ademola Lookman, Arda Güler, Scott McTominay, Serhou Guirassy, Victor Osimhen")
tier('B', "Thibaut Courtois, Gianluigi Donnarumma, Alisson Becker, Manuel Neuer, David Raya, Joan Garcia, Jan Oblak, Lucas Chevalier, Josep Martínez, "
         "Aurélien Tchouaméni, Dean Huijsen, Ibrahima Konaté, Trent Alexander-Arnold, Álvaro Carreras, Marc Cucurella, Rodrygo, Bernardo Silva, Denzel Dumfries, "
         "Dayot Upamecano, Jonathan Tah, Aleksandar Pavlović, Ryan Gravenberch, Virgil van Dijk, Jeremie Frimpong, Milos Kerkez, "
         "Jérémy Doku, Omar Marmoush, Savinho, Rúben Dias, Joško Gvardiol, Marc Guéhi, William Saliba, Gabriel Magalhães, Martín Zubimendi, Jurriën Timber, "
         "Gabriel Martinelli, Noni Madueke, Kai Havertz, Bruno Guimarães, Jules Koundé, Pau Cubarsí, Alejandro Balde, Dani Olmo, Frenkie de Jong, Fermín López, Karim Adeyemi, "
         "Alexander Sørloth, Jonathan David, Álex Baena, Pablo Barrios, Cristian Romero, Álex Grimaldo, Marquinhos, Willian Pacho, Fabián Ruiz, Maghnes Akliouche, Ferran Torres, "
         "Manuel Akanji, Kevin De Bruyne, Rasmus Højlund, Bruno Fernandes, Bryan Mbeumo, Matheus Cunha, Benjamin Šeško, Antony, Nico Paz, Moise Kean, Mason Greenwood, Rafael Leão, Luis Suárez, Samu Aghehowa")
tier('C', "Eduardo Camavinga, Éder Militão, Antonio Rüdiger, Brahim Díaz, Endrick, Yan Diomande, Kim Min-jae, Alphonso Davies, Serge Gnabry, Konrad Laimer, Josip Stanišić, Tom Bischof, Lennart Karl, "
         "Ronald Araújo, Jérémy Jacquet, Giovanni Leoni, Conor Bradley, Federico Chiesa, Víctor Muñoz, Rayan Aït-Nouri, Abdukodir Khusanov, Nico O'Reilly, Nico González, Mateo Kovačić, Matheus Nunes, Rico Lewis, Jack Grealish, "
         "Riccardo Calafiori, Piero Hincapié, Mikel Merino, Gabriel Jesus, Christos Tzolis, Ezri Konsa, Ben White, Cristhian Mosquera, Myles Lewis-Skelly, "
         "João Cancelo, Eric García, Gerard Martín, Gavi, Marc Bernal, Marcos Llorente, Koke, Giuliano Simeone, Dávid Hancko, Robin Le Normand, Marc Pubill, Morten Hjulmand, Johnny Cardoso, Lee Kang-in, "
         "Benjamin Pavard, Yann Aurel Bisseck, Piotr Zieliński, Petar Sučić, Henrikh Mkhitaryan, John Stones, Carlos Augusto, Ange-Yoan Bonny, Pio Esposito, Luis Henrique, Curtis Jones, Djed Spence, "
         "Warren Zaïre-Emery, Illia Zabarnyi, Lucas Hernandez, Mika Godts")
tier('F', "Cassiano Kiala, Guido Della Rovere, Bastian Assomo, Deniz Ofli, Erblin Osmani, Bara Ndiaye, Vincent Manuba, Filip Pavić, David Santos Daiber, Maycon Cardozo, "
         "Trey Nyoni, Stefan Bajcetic, James McConnell, Joshua Wilson-Esbrand, Kalvin Phillips, Xavi Espart, Arnau Ortiz, Jorge Domínguez, Dani Martínez, Thiago Pitarch, Carlos Espí, Senny Mayulu, Quentin Ndjantou, Dro Fernández")

# ---------------- squadre medie ----------------
tier('B', "Kevin De Bruyne")
tier('C', "Paulo Dybala, Artem Dovbyk, Donyell Malen, Matías Soulé, Manu Koné, Mile Svilar, Jobe Bellingham, Gregor Kobel, Nico Schlotterbeck, Ethan Nwaneri, Fábio Silva, Felix Nmecha, Maximilian Beier, "
         "Geny Catamo, Maximiliano Araújo, Rodrigo Zalazar, Fotis Ioannidis, Rui Silva, Gonçalo Inácio, "
         "Nicolas Jackson, Alejandro Garnacho, John McGinn, Amadou Onana, Boubacar Kamara, Leon Goretzka, Emiliano Buendía, Tammy Abraham, João Gomes, Zion Suzuki, "
         "Santiago Giménez, Pepê, Borja Sainz, Victor Froholdt, Gabri Veiga, Diogo Costa, William Gomes, "
         "Amad Diallo, Marcus Rashford, Kobbie Mainoo, Carlos Baleba, Youri Tielemans, Senne Lammens, "
         "Nicolò Tresoldi, Carlos Forbs, Hans Vanaken, Romeo Vermant, Yann Sommer, "
         "Abde Ezzalzouli, Cucho Hernández, Isco, Giovani Lo Celso, Álvaro Valles, "
         "Ricardo Pepi, Guus Til, Couhaib Driouech, Ivan Perišić, Dennis Man, Nick Olij, "
         "Anis Hadj Moussa, Sem Steijn, Tjark Ernst, Olivier Giroud, Hákon Haraldsson, Matias Fernandez-Pardo, Hamza Igamane, Berke Özer, "
         "David Neres, Matteo Politano, Stanislav Lobotka, André-Frank Zambo Anguissa, Giovanni Di Lorenzo, Alessandro Buongiorno, Amir Rrahmani, Vanja Milinković-Savić, Noa Lang, Lorenzo Lucca, "
         "Antonio Nusa, Johan Bakayoko, Christoph Baumgartner, David Raum, Christopher Nkunku, Brajan Gruda, Assan Ouédraogo, Maarten Vandevoordt, "
         "Alberto Moleiro, Georges Mikautadze, Nicolas Pépé, Gerard Moreno, Ayoze Pérez, Luiz Júnior, "
         "Marco Asensio, Kerem Aktürkoğlu, Talisca, N'Golo Kanté, Mattéo Guendouzi, Ederson, Romelu Lukaku, "
         "Leroy Sané, İlkay Gündoğan, Barış Alper Yılmaz, Gabriel Sara, Uğurcan Çakır, Aleksey Batrakov, "
         "Deniz Undav, Ermedin Demirović, Bilal El Khannouss, Angelo Stiller, Jamie Leweling, "
         "Martin Baturina, Anastasios Douvikas, Assane Diao, Jesús Rodríguez, Máximo Perrone, Jean Butez, "
         "Florian Thauvin, Odsonne Édouard, Abdallah Sima, Robin Risser")
tier('D', "Lorenzo Pellegrini, Bryan Cristante, Neil El Aynaoui, Evan Ndicka, Gianluca Mancini, Wesley, Angeliño, Mario Hermoso, Zeki Çelik, Niccolò Pisilli, Daniele Ghilardi, Devyne Rensch, Robinio Vaz, "
         "Waldemar Anton, Ramy Bensebaini, Marcel Sabitzer, Julian Ryerson, Daniel Svensson, Emre Can, Konstantinos Karetsas, Carney Chukwuemeka, Joey Veerman, Giannis Konstantelias, "
         "Ousmane Diomande, Zeno Debast, Eduardo Quaresma, Georgios Vagiannidis, Iván Fresneda, João Simões, Giorgi Kochorashvili, Luis Guilherme, Silas Andersen, "
         "Matty Cash, Pau Torres, Ian Maatsen, Victor Lindelöf, Tyrone Mings, Aaron Wan-Bissaka, Ross Barkley, Matteo Ruggeri, Johan Manzambi, Lamare Bogarde, Taylor Harwood-Bellis, "
         "Jakub Kiwior, Jan Bednarek, Alberto Costa, Seko Fofana, Alan Varela, Martim Fernandes, Francisco Moura, Dominik Prpić, Oskar Pietuszewski, André Silva, Gabriel Mec, Hwang In-beom, "
         "Diogo Dalot, Matthijs de Ligt, Lisandro Martínez, Leny Yoro, Harry Maguire, Noussair Mazraoui, Luke Shaw, Patrick Dorgu, Manuel Ugarte, Mason Mount, Joshua Zirkzee, "
         "Joel Ordóñez, Brandon Mechele, Jorne Spileers, Joaquin Seys, Kyriani Sabbe, Hugo Siquet, Cheveyo Tsawa, Freddie Potts, Hugo Vetlesen, Mamadou Diakhon, Lee Han-beom, "
         "Héctor Bellerín, Natan, Diego Llorente, Valentín Gómez, Marc Roca, Pablo Fornals, Rodrigo Riquelme, Nelson Deossa, Álvaro Fidalgo, Junior Firpo, Fran García, Aitor Ruibal, "
         "Jerdy Schouten, Sergiño Dest, Ryan Flamingo, Armando Obispo, Mauro Júnior, Paul Wanner, Alassane Pléa, Ruben van Bommel, Yarek Gasiorowski, Filip Kostić, Kiliann Sildillia, Sven Mijnans, Esmir Bajraktarević, Lutsharel Geertruida, "
         "Luciano Valente, Jakub Moder, Reiss Nelson, Nacho Ferri, Gonçalo Borges, Tsuyoshi Watanabe, Givairo Read, Gijs Smal, Thomas Beelen, Oussama Targhalline, Jordan Bos, Jeremiah St. Juste, Gaoussou Diarra, "
         "Ethan Mbappé, Benjamin André, Ayyoub Bouaddi, Alexsandro, Romain Perraud, Calvin Verdonk, Osame Sahraoui, Ngal'ayel Mukau, Félix Correia, Tanguy Nianzou, Mohamed Bayo, "
         "Mathías Olivera, Leonardo Spinazzola, Sam Beukema, Billy Gilmour, Rafa Marín, Pasquale Mazzocchi, Giovane, Antonio Vergara, Alisson Santos, "
         "Nicolas Seiwald, Castello Lukeba, Willi Orbán, Maxime Estève, Ridle Baku, Rocco Reitz, Ezechiel Banzuzi, Marc Guiu, Benjamin Henrichs, Tidiam Gomis, "
         "Tani Oluwaseyi, Tajon Buchanan, Santi Comesaña, Pape Gueye, Juan Foyth, Renato Veiga, Santiago Mouriño, Alex Freeman, Sergi Cardona, Logan Costa, Pau Navarro, Ilias Akhomach, "
         "Milan Škriniar, Nélson Semedo, Nathan Aké, Jayden Oosterwolde, Archie Brown, Sofyan Amrabat, İrfan Can Kahveci, Oğuz Aydın, Vedat Muriqi, Dorgeles Nene, Levent Mercan, Çağlar Söyüncü, İsmail Yüksek, "
         "Davinson Sánchez, Wilfried Singo, Ismail Jakobs, Abdülkerim Bardakcı, Lucas Torreira, Mario Lemina, Yunus Akgün, Roland Sallai, Eren Elmalı, Lesley Ugochukwu, "
         "Chris Führich, Maximilian Mittelstädt, Tiago Tomás, Atakan Karazor, Jeff Chabot, Finn Jeltsch, Ramon Hendriks, Josha Vagnoman, Lorenz Assignon, Ameen Al-Dakhil, Nikolas Nartey, Leonidas Stergiou, Fabian Bredlow, "
         "Lucas Da Cunha, Maxence Caqueret, Samuele Ricci, Álex Valle, Jacobo Ramón, Marc-Oliver Kempf, Ivan Smolčić, Trevoh Chalobah, Yan Couto, Jayden Addai, Willy Kambwala, Alberto Dossena, "
         "Florian Sotoca, Mamadou Sangaré, Amadou Haidara, Michaël Cuisance, Jonathan Gradit, Matthieu Udol, Saud Abdulhamid, Ruben Aguilar, Samson Baidoo, Ismaëlo Ganiou, Andrija Bulatović")

# ---------------- squadre piccole ----------------
tier('D', "Eguinaldo, Pedrinho, Lassina Traoré, Kauã Elias, Marlon Gomes, "
         "Tomáš Chorý, Lukáš Provod, Mojmír Chytil, Ivan Schranz, "
         "Tigran Barseghyan, Andraž Šporar, "
         "Luka Jović, Aboubakary Koïta, Lovro Majer, Răzvan Marin, Oleksandr Zubkov, "
         "Saša Kalajdžić, Jens Petter Hauge")
tier('E', "Dmytro Riznyk, Mykola Matviyenko, Valeriy Bondar, Isaque, Newerton, Oleh Ocheretko, Dmytro Kryskiv, Irakli Azarovi, Vinicius Tobias, Pedro Henrique, Gabriel Carvalho, Alisson Santana, Marlon Santos, Alaa Ghram, Oleksandr Karavayev, "
         "Jindřich Staněk, Youssoupha Sanyang, David Moses, David Zima, Tomáš Holeš, David Jurásek, Igoh Ogbu, Štěpán Chaloupek, Michal Sadílek, Toumani Diakité, Adonija Ouanda, Oskar Kubiak, "
         "Dominik Takáč, Mykola Kukharevych, Nino Marcelli, Danylo Ihnatenko, Kevin Wimmer, Jurij Medveděv, Kenan Bajrić, César Blackman, Rahim Ibrahim, Peter Pokorný, Kelvin Ofori, Artur Gajdoš, "
         "Thomas Strakosha, Domagoj Vida, Harold Moukoudi, Lazaros Rota, Stavros Pilios, Dereck Kutesa, Barnabás Varga, Mijat Gaćinović, Kaan Kairinen, Petros Mantalos, Filipe Relvas, Kervin Arriaga, "
         "Lukas Jungwirth, Moses Usor, Samuel Adeniran, Sascha Horvath, Robert Ljubičić, George Bello, Art Smakaj, Florian Flecker, Andrés Andrade, Alessandro Schöpf, Christoph Lang, Kasper Jørgensen, "
         "Nicholas D'Agostino, Veton Berisha, Kristoffer Askildsen, Joe Bell, Arild Østbø, Essiën Bassey, Henrik Heggheim, Kristoffer Haugen, Zlatko Tripić, Romano Postema, Henrik Bjørdal, Peter Christiansen, Erik Botheim, Viljar Vevatne, "
         "Amin Ramazanov, Joy-Lance Mickels, Steve Solvet, Tymoteusz Puchacz, Xander Severina, Zinédine Ould Khaled, Ivan Lepinjica, Kaheem Parris, Christian Nwachukwu, Carlos Eduardo, Akim Zedadka, Veljko Simić, Younes Lachaab, "
         "Patrick Berg, Andreas Helmersen, Ole Didrik Blomberg, Nikita Haikin, Odin Bjørtuft, Jostein Gundersen, Fredrik Sjøvold, Håkon Evjen, Ulrik Saltnes, Sondre Brunstad Fet, Isak Dybvik Määttä, Sondre Auklend, Fredrik André Bjørkan, Haitam Aleesami, Ola Brynhildsen")


def price(name, club, role):
    if name in T:
        t = T[name]
    elif role == 'P':
        t = 'F'                       # portiere di riserva
    else:
        t = DEFAULT(club)
    return max(1, round(TIER[t] * ROLE_K[role])), t


def build():
    rows, seen = [], {}
    for club, block in ROSTERS.items():
        for line in block.strip().splitlines():
            name, pos = [x.strip() for x in line.split('|')]
            role = ROLE_FIX.get(name, POS[pos])
            p, t = price(name, club, role)
            if name in seen:
                print('DUPLICATO:', name, seen[name], club, file=sys.stderr)
            seen[name] = club
            rows.append({'nome': name, 'ruolo': role, 'squadra': club, 'prezzo': p, 'fascia': t})
    return rows


if __name__ == '__main__':
    rows = build()
    unknown = [n for n in T if not any(r['nome'] == n for r in rows)]
    if unknown:
        print('Nomi nelle fasce non presenti nelle rose:', unknown, file=sys.stderr)
    out = os.path.join(os.path.dirname(__file__), '..', 'giocatori-champions-2026-27.csv')
    with open(out, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f, delimiter=';')
        w.writerow(['nome', 'ruolo', 'squadra', 'prezzo'])
        for r in sorted(rows, key=lambda r: (r['squadra'], 'PDCA'.index(r['ruolo']), -r['prezzo'])):
            w.writerow([r['nome'], r['ruolo'], r['squadra'], r['prezzo']])
    print(len(rows), 'giocatori scritti in', os.path.abspath(out))
