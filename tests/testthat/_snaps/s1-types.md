# format and print show values with probabilities and a dim footer

    Code
      print(s1_dec())
    Output
                   a              b              c 
       TRUE (p=0.90) FALSE (p=0.20)  TRUE (p=0.70) 
      jev-1.13.0 . calibrated . 2026-09-29

---

    Code
      print(s1_cho())
    Output
                   x              y 
      liver (p=0.81)  lung (p=0.70) 
      jev-1.13.0 . calibrated . 2026-09-29

---

    Code
      print(new_gptr_score(numeric(), "a", NULL, numeric()))
    Output
      <gptr_score[0]>

