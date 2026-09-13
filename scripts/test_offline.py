"""Offline sanity check for vox_scraper's parsing functions, using real
HTML fragments captured from the live site (no network needed here)."""

from datetime import date

from bs4 import BeautifulSoup
from vox_scraper import Movie, parse_listing, parse_detail, _is_riyadh_branch

LISTING_FRAGMENT = """
<div>
<article class="movie-summary" data-slug="the-odyssey" data-identifier="the-odyssey" data-title="The Odyssey">
  <a href="/movies/the-odyssey">
    <img class="poster" src="https://assets.voxcinemas.com/posters/P_HO00013488_1783655908489.jpg" loading="lazy" alt="Movie poster for The Odyssey" width="440" height="686" data-ot-ignore="">
  </a>
  <h3><a href="/movies/the-odyssey">The Odyssey</a></h3>
  <p><span class="classification c-r15">R15</span></p>
  <p class="language"><strong>Language:</strong> English</p>
  <a class="action secondary " href="/movies/the-odyssey#showtimes">Showtimes</a>
</article>
<article class="movie-summary" data-slug="avengers-endgame-encore" data-identifier="avengers-endgame-encore" data-title="Avengers Endgame: Encore">
  <a href="/movies/avengers-endgame-encore">
    <img class="poster" src="/assets/images/placeholder-poster.webp" loading="lazy" alt="Movie poster placeholder" width="440" height="686">
  </a>
  <h3><a href="/movies/avengers-endgame-encore">Avengers Endgame: Encore</a></h3>
  <p><span class="classification c-pg12">PG12</span></p>
  <p class="language"><strong>Language:</strong> English</p>
  <a class="action secondary " href="/movies/avengers-endgame-encore#showtimes">Showtimes</a>
</article>
</div>
"""

DETAIL_ASIDE = """
<aside>
  <p><strong>Genre:</strong> Adventure</p>
  <p><strong>Running Time:</strong> 175 min</p>
  <p><strong>Release Date:</strong> 16 July 2026</p>
  <p><strong>Starring:</strong> Robert Pattinson, Anne Hathaway, Zendaya ,, Tom Holland, Matt Damon</p>
  <p><strong>Language:</strong> English</p>
  <p><strong>Subtitle(s):</strong> Arabic</p>
</aside>
"""

# Trimmed real showtimes section (kept multiple branches + the tricky
# "Private Cinema" tooltip case + a sold-out entry + a multi-screen branch).
DETAIL_SHOWTIMES = """
<section id="showtimes">
  <h2 class="highlight">The Odyssey - Showtimes</h2>
  <div class="dates">
    <h3 class="highlight">Al Qasr Mall - Riyadh</h3>
    <ol class="showtimes">
      <li><strong>MAX</strong>
        <ol><li data-id="0041-282953"><a class="action showtime" href="https://ksa.voxcinemas.com/booking/0041-282953" data-id="0041-282953">11:45pm </a></li></ol>
      </li>
    </ol>
    <h3 class="highlight">Century Corner - Riyadh</h3>
    <ol class="showtimes">
      <li><strong>IMAX</strong>
        <ol>
          <li data-id="0106-78863"><a class="action showtime" href="https://ksa.voxcinemas.com/booking/0106-78863" data-id="0106-78863">6:15pm </a></li>
          <li data-id="0106-78864"><a class="action showtime" href="https://ksa.voxcinemas.com/booking/0106-78864" data-id="0106-78864">9:45pm </a></li>
        </ol>
      </li>
      <li><strong>Private Cinema <a class="information tooltip-target tooltip" role="tooltip" data-html="tooltip-content-x" aria-expanded="false">i</a>
          <div id="tooltip-content-x" style="display: none;">This session can be customized after you book (content, F&amp;B)</div>
        </strong>
        <ol><li data-id="0106-79243"><span class="action showtime unavailable">11:30pm</span></li></ol>
      </li>
    </ol>
    <h3 class="highlight">Kingdom Centre - Riyadh</h3>
    <ol class="showtimes">
      <li><strong>VIP</strong>
        <ol>
          <li data-id="0043-200603"><span class="action showtime unavailable">9:30pm</span></li>
          <li data-id="0043-200604"><a class="action showtime" href="https://ksa.voxcinemas.com/booking/0043-200604" data-id="0043-200604">1:15am </a></li>
        </ol>
      </li>
    </ol>
  </div>
</section>
"""


def test_listing():
    soup = BeautifulSoup(LISTING_FRAGMENT, "html.parser")
    movies = parse_listing(soup)
    assert len(movies) == 2, f"expected 2 movies, got {len(movies)}"

    m1 = movies[0]
    assert m1.title == "The Odyssey"
    assert m1.slug == "the-odyssey"
    assert m1.poster_url == "https://assets.voxcinemas.com/posters/P_HO00013488_1783655908489.jpg"
    assert m1.rating == "R15"
    assert m1.language == "English"

    m2 = movies[1]
    assert m2.title == "Avengers Endgame: Encore"
    assert m2.poster_url == "/assets/images/placeholder-poster.webp"
    print("parse_listing: OK ->", [ (m.title, m.duration_minutes) for m in movies])


def test_detail():
    movie = Movie(title="The Odyssey", slug="the-odyssey", poster_url=None, rating="R15", language="English")
    soup = BeautifulSoup(DETAIL_ASIDE + DETAIL_SHOWTIMES, "html.parser")
    parse_detail(soup, movie, date(2026, 9, 13))

    assert movie.genre == "Adventure", movie.genre
    assert movie.duration_minutes == 175, movie.duration_minutes
    assert movie.release_date == "16 July 2026", movie.release_date
    assert movie.subtitles == "Arabic", movie.subtitles

    branches = {s.branch for s in movie.showtimes_today}
    assert branches == {"Al Qasr Mall - Riyadh", "Century Corner - Riyadh", "Kingdom Centre - Riyadh"}, branches

    # Private Cinema screen type should be clean text, no tooltip "i" glued on
    private = [s for s in movie.showtimes_today if s.screen_type.startswith("Private Cinema")]
    assert len(private) == 1
    assert private[0].screen_type == "Private Cinema", repr(private[0].screen_type)
    assert private[0].sold_out is True

    sold_out_count = sum(1 for s in movie.showtimes_today if s.sold_out)
    assert sold_out_count == 2, sold_out_count

    total = len(movie.showtimes_today)
    assert total == 6, total  # 1 + (2+1) + 2

    # branch_code comes from the data-id prefix ("0041-282953" -> "0041")
    by_branch = {s.branch: s.branch_code for s in movie.showtimes_today}
    assert by_branch["Al Qasr Mall - Riyadh"] == "0041", by_branch
    assert by_branch["Century Corner - Riyadh"] == "0106", by_branch
    assert by_branch["Kingdom Centre - Riyadh"] == "0043", by_branch

    # 11:45pm on 2026-09-13 stays same-day; 1:15am rolls to 2026-09-14.
    same_day = next(s for s in movie.showtimes_today if s.time == "11:45pm")
    assert same_day.show_time_iso.startswith("2026-09-13T23:45:00"), same_day.show_time_iso
    rolled = next(s for s in movie.showtimes_today if s.time == "1:15am")
    assert rolled.show_time_iso.startswith("2026-09-14T01:15:00"), rolled.show_time_iso

    print("parse_detail: OK ->", movie.duration_minutes, "min,", total, "showtimes across", len(branches), "branches")
    print("  branch codes:", by_branch)
    print("  same-day time:", same_day.show_time_iso, "| rolled-over time:", rolled.show_time_iso)


# A non-Riyadh branch (Jeddah) alongside a Riyadh one, plus the two
# name-only-override cases (see _RIYADH_BRANCH_NAME_OVERRIDES) - checks
# that only actual Riyadh branches make it into showtimes_today.
DETAIL_SHOWTIMES_MIXED_CITIES = """
<section id="showtimes">
  <div class="dates">
    <h3 class="highlight">Al Qasr Mall - Riyadh</h3>
    <ol class="showtimes">
      <li><strong>MAX</strong>
        <ol><li data-id="0041-111111"><a class="action showtime" data-id="0041-111111">7:00pm</a></li></ol>
      </li>
    </ol>
    <h3 class="highlight">Red Sea Mall - Jeddah</h3>
    <ol class="showtimes">
      <li><strong>IMAX</strong>
        <ol><li data-id="0038-222222"><a class="action showtime" data-id="0038-222222">7:30pm</a></li></ol>
      </li>
    </ol>
    <h3 class="highlight">The Esplanade</h3>
    <ol class="showtimes">
      <li><strong>VIP</strong>
        <ol><li data-id="0059-333333"><a class="action showtime" data-id="0059-333333">8:00pm</a></li></ol>
      </li>
    </ol>
    <h3 class="highlight">Cinema Aljadidah</h3>
    <ol class="showtimes">
      <li><strong>Standard</strong>
        <ol><li data-id="0109-444444"><a class="action showtime" data-id="0109-444444">8:30pm</a></li></ol>
      </li>
    </ol>
  </div>
</section>
"""


def test_riyadh_only_filtering():
    assert _is_riyadh_branch("Al Qasr Mall - Riyadh") is True
    assert _is_riyadh_branch("Red Sea Mall - Jeddah") is False
    assert _is_riyadh_branch("The Esplanade") is True  # name-only override
    assert _is_riyadh_branch("Cinema Aljadidah") is False  # name-only override (AlUla)

    movie = Movie(title="Test Movie", slug="test-movie", poster_url=None, rating=None, language=None)
    soup = BeautifulSoup(DETAIL_SHOWTIMES_MIXED_CITIES, "html.parser")
    parse_detail(soup, movie, date(2026, 9, 13))

    branches = {s.branch for s in movie.showtimes_today}
    assert branches == {"Al Qasr Mall - Riyadh", "The Esplanade"}, branches
    assert len(movie.showtimes_today) == 2, len(movie.showtimes_today)
    print("riyadh-only filtering: OK -> kept", branches, "dropped Jeddah + Cinema Aljadidah")


if __name__ == "__main__":
    test_listing()
    test_detail()
    test_riyadh_only_filtering()
    print("\nAll offline checks passed.")
