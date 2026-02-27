/* ======================================
   DREWWOOD — Script
   ====================================== */

document.addEventListener('DOMContentLoaded', () => {

  // ------- Preloader -------
  const preloader = document.getElementById('preloader');
  window.addEventListener('load', () => {
    setTimeout(() => {
      preloader.classList.add('loaded');
    }, 600);
  });
  // Fallback — ukryj po 3s nawet jeśli load nie odpali
  setTimeout(() => preloader.classList.add('loaded'), 3000);

  // ------- Rok w stopce -------
  const yearEl = document.getElementById('year');
  if (yearEl) yearEl.textContent = new Date().getFullYear();

  // ------- Sezonowe Hero (X–II = drewno / III–IX = ogród) -------
  const month = new Date().getMonth(); // 0 = styczeń
  const isGardenSeason = month >= 2 && month <= 8; // marzec(2)–wrzesień(8)

  if (isGardenSeason) {
    // Pokaż tło ogrodowe, ukryj ogień
    const bgFire = document.querySelector('.hero-bg-fire');
    const bgGarden = document.querySelector('.hero-bg-garden');
    if (bgFire) bgFire.style.opacity = '0';
    if (bgGarden) bgGarden.style.opacity = '1';

    // Zamień treści
    document.querySelectorAll('.hero-heading-fire, .hero-lead-fire').forEach(el => el.style.display = 'none');
    document.querySelectorAll('.hero-heading-garden, .hero-lead-garden').forEach(el => el.style.display = '');

    // Zmień CTA
    const secondaryCta = document.querySelector('.hero-cta-secondary');
    if (secondaryCta) {
      secondaryCta.textContent = 'Zobacz ofertę';
      secondaryCta.href = '#oferta';
    }
  }

  // ------- Nawigacja — scroll efekt -------
  const navbar = document.getElementById('navbar');

  function handleNavScroll() {
    if (window.scrollY > 60) {
      navbar.classList.add('scrolled');
    } else {
      navbar.classList.remove('scrolled');
    }
  }

  window.addEventListener('scroll', handleNavScroll, { passive: true });
  handleNavScroll();

  // ------- Hamburger menu -------
  const menuToggle = document.getElementById('menuToggle');
  const navLinks = document.getElementById('navLinks');

  if (menuToggle && navLinks) {
    menuToggle.addEventListener('click', () => {
      menuToggle.classList.toggle('active');
      navLinks.classList.toggle('show');
      document.body.style.overflow = navLinks.classList.contains('show') ? 'hidden' : '';
    });

    navLinks.querySelectorAll('a').forEach(link => {
      link.addEventListener('click', () => {
        menuToggle.classList.remove('active');
        navLinks.classList.remove('show');
        document.body.style.overflow = '';
      });
    });
  }

  // ------- Smooth scroll -------
  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', (e) => {
      const target = document.querySelector(anchor.getAttribute('href'));
      if (target) {
        e.preventDefault();
        target.scrollIntoView({ behavior: 'smooth' });
      }
    });
  });

  // ------- Zakładki produktowe -------
  const tabBtns = document.querySelectorAll('.tab-btn');
  const tabPanels = document.querySelectorAll('.tab-panel');

  tabBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      const tabId = btn.getAttribute('data-tab');

      tabBtns.forEach(b => b.classList.remove('active'));
      tabPanels.forEach(p => p.classList.remove('active'));

      btn.classList.add('active');
      const panel = document.getElementById('tab-' + tabId);
      if (panel) panel.classList.add('active');
    });
  });

  // ------- Back to top -------
  const backToTop = document.getElementById('backToTop');
  if (backToTop) {
    window.addEventListener('scroll', () => {
      if (window.scrollY > 600) {
        backToTop.classList.add('visible');
      } else {
        backToTop.classList.remove('visible');
      }
    }, { passive: true });

    backToTop.addEventListener('click', () => {
      window.scrollTo({ top: 0, behavior: 'smooth' });
    });
  }

  // ------- Animacje na scroll (Intersection Observer) -------
  const animElements = document.querySelectorAll('.animate-on-scroll');

  if ('IntersectionObserver' in window) {
    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          const siblings = entry.target.parentElement.querySelectorAll('.animate-on-scroll');
          let siblingIndex = 0;
          siblings.forEach((sib, i) => {
            if (sib === entry.target) siblingIndex = i;
          });

          setTimeout(() => {
            entry.target.classList.add('visible');
          }, siblingIndex * 100);

          observer.unobserve(entry.target);
        }
      });
    }, {
      threshold: 0.1,
      rootMargin: '0px 0px -50px 0px'
    });

    animElements.forEach(el => observer.observe(el));
  } else {
    animElements.forEach(el => el.classList.add('visible'));
  }

  // ------- Animacja liczników -------
  const statNumbers = document.querySelectorAll('.stat-number[data-target]');

  if ('IntersectionObserver' in window && statNumbers.length) {
    const countObserver = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          animateCount(entry.target);
          countObserver.unobserve(entry.target);
        }
      });
    }, { threshold: 0.5 });

    statNumbers.forEach(el => countObserver.observe(el));
  }

  function animateCount(el) {
    const target = parseInt(el.getAttribute('data-target'), 10);
    const duration = 2000;
    const start = performance.now();

    function update(now) {
      const elapsed = now - start;
      const progress = Math.min(elapsed / duration, 1);
      const eased = 1 - Math.pow(1 - progress, 3);
      el.textContent = Math.round(eased * target);
      if (progress < 1) {
        requestAnimationFrame(update);
      }
    }

    requestAnimationFrame(update);
  }

  // ------- Gallery — pokaż więcej -------
  const galleryMoreBtn = document.getElementById('galleryMoreBtn');
  const galleryGrid = document.querySelector('.gallery-grid');

  if (galleryMoreBtn && galleryGrid) {
    galleryMoreBtn.addEventListener('click', () => {
      galleryGrid.classList.toggle('gallery-expanded');
      const expanded = galleryGrid.classList.contains('gallery-expanded');
      galleryMoreBtn.innerHTML = expanded
        ? 'Pokaż mniej <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 9l6 6 6-6"/></svg>'
        : 'Pokaż więcej zdjęć <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 9l6 6 6-6"/></svg>';
      galleryMoreBtn.classList.toggle('rotated', expanded);

      // Trigger animation on newly visible items
      if (expanded) {
        document.querySelectorAll('.gallery-hidden').forEach((item, i) => {
          setTimeout(() => item.classList.add('visible'), i * 80);
        });
      }
    });
  }

  // ------- Lightbox galerii -------
  const lightbox = document.getElementById('lightbox');
  const lightboxImg = document.getElementById('lightboxImg');
  const galleryItems = document.querySelectorAll('.gallery-item');
  let currentIndex = 0;

  const imageUrls = [];
  galleryItems.forEach((item, i) => {
    const src = item.getAttribute('data-src');
    if (src) imageUrls.push(src);

    item.addEventListener('click', () => {
      currentIndex = i;
      openLightbox(imageUrls[currentIndex]);
    });
  });

  function openLightbox(src) {
    lightboxImg.src = src;
    lightbox.classList.add('active');
    document.body.style.overflow = 'hidden';
  }

  function closeLightbox() {
    lightbox.classList.remove('active');
    document.body.style.overflow = '';
  }

  function nextImage() {
    currentIndex = (currentIndex + 1) % imageUrls.length;
    lightboxImg.src = imageUrls[currentIndex];
  }

  function prevImage() {
    currentIndex = (currentIndex - 1 + imageUrls.length) % imageUrls.length;
    lightboxImg.src = imageUrls[currentIndex];
  }

  if (lightbox) {
    lightbox.querySelector('.lightbox-close').addEventListener('click', closeLightbox);
    lightbox.querySelector('.lightbox-prev').addEventListener('click', prevImage);
    lightbox.querySelector('.lightbox-next').addEventListener('click', nextImage);

    lightbox.addEventListener('click', (e) => {
      if (e.target === lightbox) closeLightbox();
    });

    // Klawiatura
    document.addEventListener('keydown', (e) => {
      if (!lightbox.classList.contains('active')) return;
      if (e.key === 'Escape') closeLightbox();
      if (e.key === 'ArrowRight') nextImage();
      if (e.key === 'ArrowLeft') prevImage();
    });

    // Swipe na mobile
    let touchStartX = 0;
    let touchEndX = 0;

    lightbox.addEventListener('touchstart', (e) => {
      touchStartX = e.changedTouches[0].screenX;
    }, { passive: true });

    lightbox.addEventListener('touchend', (e) => {
      touchEndX = e.changedTouches[0].screenX;
      const diff = touchStartX - touchEndX;
      if (Math.abs(diff) > 50) {
        if (diff > 0) nextImage();
        else prevImage();
      }
    }, { passive: true });
  }

});
